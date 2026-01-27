package main

import (
	"embed"
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

//go:embed templates/*
var templateFS embed.FS

var (
	showsDir     = getEnv("SHOWS_DIR", "/var/lib/radio/shows")
	listenAddr   = getEnv("LISTEN_ADDR", ":8080")
	timezone     = getEnv("TZ", "Europe/London")
	saturdayTime = getEnv("SATURDAY_TIME", "18:00")
	sundayTime   = getEnv("SUNDAY_TIME", "10:00")
)

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

type Show struct {
	Filename string
	Slot     string
	DateTime time.Time
	Size     int64
	SizeStr  string
}

type UpcomingDate struct {
	Value     string // 2025-02-01
	Label     string // Saturday, Feb 1
	Scheduled bool   // true if a show is already scheduled
}

type PageData struct {
	Shows        []Show
	Timezone     string
	SaturdayTime string
	SundayTime   string
	Error        string
	Success      string
	Saturdays    []UpcomingDate
	Sundays      []UpcomingDate
}

func main() {
	if err := os.MkdirAll(showsDir, 0755); err != nil {
		log.Fatalf("Failed to create shows directory: %v", err)
	}

	http.HandleFunc("/", handleIndex)
	http.HandleFunc("/upload", handleUpload)
	http.HandleFunc("/delete", handleDelete)
	http.HandleFunc("/play/", handlePlay)

	// Reschedule any future shows (recovers from reboot)
	rescheduleAllShows()

	log.Printf("Scheduler listening on %s", listenAddr)
	log.Printf("Shows directory: %s", showsDir)
	log.Printf("Timezone: %s", timezone)
	log.Fatal(http.ListenAndServe(listenAddr, nil))
}

func handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	tmpl, err := template.ParseFS(templateFS, "templates/index.html")
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	shows, err := listShows()
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	loc, _ := time.LoadLocation(timezone)
	now := time.Now().In(loc)

	data := PageData{
		Shows:        shows,
		Timezone:     timezone,
		SaturdayTime: saturdayTime,
		SundayTime:   sundayTime,
		Error:        r.URL.Query().Get("error"),
		Success:      r.URL.Query().Get("success"),
		Saturdays:    upcomingWeekdays(now, time.Saturday, 8),
		Sundays:      upcomingWeekdays(now, time.Sunday, 8),
	}

	tmpl.Execute(w, data)
}

func handleUpload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Redirect(w, r, "./?error=Method+not+allowed", http.StatusSeeOther)
		return
	}

	r.ParseMultipartForm(500 << 20) // 500MB max

	slot := r.FormValue("slot")
	date := r.FormValue("date")
	datetime := r.FormValue("datetime") // For test slots

	loc, _ := time.LoadLocation(timezone)
	var filename string
	var scheduledTime time.Time
	var isQuickTest bool

	switch slot {
	case "quicktest":
		isQuickTest = true
		// Time will be computed after upload completes
		// Use a unique temp filename - will be renamed after upload
		filename = fmt.Sprintf("quicktest-temp-%d", time.Now().UnixNano())

	case "test":
		if datetime == "" {
			http.Redirect(w, r, "./?error=Datetime+required+for+test", http.StatusSeeOther)
			return
		}
		parsed, err := time.ParseInLocation("2006-01-02T15:04", datetime, loc)
		if err != nil {
			http.Redirect(w, r, "./?error=Invalid+datetime+format", http.StatusSeeOther)
			return
		}
		if parsed.Before(time.Now().In(loc)) {
			http.Redirect(w, r, "./?error=Cannot+schedule+in+the+past", http.StatusSeeOther)
			return
		}
		scheduledTime = parsed
		filename = fmt.Sprintf("test-%s", parsed.Format("2006-01-02T15-04"))

	case "saturday", "sunday":
		if date == "" {
			http.Redirect(w, r, "./?error=Date+required", http.StatusSeeOther)
			return
		}
		parsed, err := time.ParseInLocation("2006-01-02", date, loc)
		if err != nil {
			http.Redirect(w, r, "./?error=Invalid+date+format", http.StatusSeeOther)
			return
		}
		expectedDay := time.Saturday
		timeStr := saturdayTime
		if slot == "sunday" {
			expectedDay = time.Sunday
			timeStr = sundayTime
		}
		if parsed.Weekday() != expectedDay {
			http.Redirect(w, r, "./?error=Date+must+be+a+"+slot, http.StatusSeeOther)
			return
		}
		// Combine date with slot time
		scheduledTime, _ = time.ParseInLocation("2006-01-02 15:04", date+" "+timeStr, loc)
		filename = fmt.Sprintf("%s-%s", slot, date)

	default:
		http.Redirect(w, r, "./?error=Invalid+slot", http.StatusSeeOther)
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		http.Redirect(w, r, "./?error=File+required", http.StatusSeeOther)
		return
	}
	defer file.Close()

	ext := strings.ToLower(filepath.Ext(header.Filename))
	if ext != ".mp3" && ext != ".ogg" && ext != ".flac" && ext != ".wav" {
		http.Redirect(w, r, "./?error=File+must+be+mp3,+ogg,+flac,+or+wav", http.StatusSeeOther)
		return
	}

	// Check for existing scheduled show at this time slot (skip for quicktest - checked later)
	if !isQuickTest {
		pattern := filepath.Join(showsDir, filename+".*")
		matches, _ := filepath.Glob(pattern)
		if len(matches) > 0 {
			http.Redirect(w, r, "./?error=A+show+is+already+scheduled+for+this+time+slot.+Delete+it+first.", http.StatusSeeOther)
			return
		}
	}

	filename = filename + ext
	destPath := filepath.Join(showsDir, filename)

	dest, err := os.Create(destPath)
	if err != nil {
		http.Redirect(w, r, "./?error=Failed+to+save+file", http.StatusSeeOther)
		return
	}
	defer dest.Close()

	if _, err := io.Copy(dest, file); err != nil {
		os.Remove(destPath)
		http.Redirect(w, r, "./?error=Failed+to+save+file", http.StatusSeeOther)
		return
	}

	// For quicktest, compute scheduled time and rename file after upload completes
	if isQuickTest {
		now := time.Now().In(loc)
		// Schedule for the next full minute
		scheduledTime = now.Truncate(time.Minute).Add(time.Minute)

		finalFilename := fmt.Sprintf("test-%s%s", scheduledTime.Format("2006-01-02T15-04"), ext)
		finalPath := filepath.Join(showsDir, finalFilename)

		// Check for duplicates at the computed time
		pattern := filepath.Join(showsDir, strings.TrimSuffix(finalFilename, ext)+".*")
		matches, _ := filepath.Glob(pattern)
		if len(matches) > 0 {
			os.Remove(destPath)
			http.Redirect(w, r, "./?error=A+show+is+already+scheduled+for+this+time+slot.+Delete+it+first.", http.StatusSeeOther)
			return
		}

		// Rename temp file to final name
		if err := os.Rename(destPath, finalPath); err != nil {
			os.Remove(destPath)
			http.Redirect(w, r, "./?error=Failed+to+rename+file", http.StatusSeeOther)
			return
		}
		destPath = finalPath
	}

	// Schedule via systemd-run
	if err := scheduleShow(destPath, scheduledTime); err != nil {
		log.Printf("Warning: failed to schedule show: %v", err)
		// Don't fail - file is saved, can be rescheduled on restart
	}

	http.Redirect(w, r, "./?success=Show+scheduled", http.StatusSeeOther)
}

func handleDelete(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Redirect(w, r, "./?error=Method+not+allowed", http.StatusSeeOther)
		return
	}

	filename := r.FormValue("filename")
	if filename == "" {
		http.Redirect(w, r, "./?error=Filename+required", http.StatusSeeOther)
		return
	}

	// Sanitize filename - allow saturday/sunday/test patterns
	pattern := regexp.MustCompile(`^(saturday|sunday)-\d{4}-\d{2}-\d{2}\.(mp3|ogg|flac|wav)$|^test-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}\.(mp3|ogg|flac|wav)$`)
	if !pattern.MatchString(filename) {
		http.Redirect(w, r, "./?error=Invalid+filename", http.StatusSeeOther)
		return
	}

	// Cancel the scheduled timer
	if err := unscheduleShow(filename); err != nil {
		log.Printf("Warning: failed to unschedule show: %v", err)
	}

	path := filepath.Join(showsDir, filename)
	if err := os.Remove(path); err != nil {
		http.Redirect(w, r, "./?error=Failed+to+delete", http.StatusSeeOther)
		return
	}

	http.Redirect(w, r, "./?success=Show+deleted", http.StatusSeeOther)
}

func handlePlay(w http.ResponseWriter, r *http.Request) {
	// Extract filename from /play/{filename}
	filename := strings.TrimPrefix(r.URL.Path, "/play/")
	if filename == "" {
		http.Error(w, "Filename required", 400)
		return
	}

	// Sanitize filename - allow saturday/sunday/test patterns
	pattern := regexp.MustCompile(`^(saturday|sunday)-\d{4}-\d{2}-\d{2}\.(mp3|ogg|flac|wav)$|^test-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}\.(mp3|ogg|flac|wav)$`)
	if !pattern.MatchString(filename) {
		http.Error(w, "Invalid filename", 400)
		return
	}

	path := filepath.Join(showsDir, filename)

	// Check file exists
	info, err := os.Stat(path)
	if err != nil {
		http.Error(w, "File not found", 404)
		return
	}

	// Set content type based on extension
	ext := strings.ToLower(filepath.Ext(filename))
	contentTypes := map[string]string{
		".mp3":  "audio/mpeg",
		".ogg":  "audio/ogg",
		".flac": "audio/flac",
		".wav":  "audio/wav",
	}
	if ct, ok := contentTypes[ext]; ok {
		w.Header().Set("Content-Type", ct)
	}

	// Support range requests for seeking
	file, err := os.Open(path)
	if err != nil {
		http.Error(w, "Cannot open file", 500)
		return
	}
	defer file.Close()

	http.ServeContent(w, r, filename, info.ModTime(), file)
}

func listShows() ([]Show, error) {
	entries, err := os.ReadDir(showsDir)
	if err != nil {
		return nil, err
	}

	loc, _ := time.LoadLocation(timezone)
	var shows []Show

	// Match saturday/sunday or test patterns
	weekendPattern := regexp.MustCompile(`^(saturday|sunday)-(\d{4}-\d{2}-\d{2})\.(mp3|ogg|flac|wav)$`)
	testPattern := regexp.MustCompile(`^(test)-(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})\.(mp3|ogg|flac|wav)$`)

	for _, e := range entries {
		if e.IsDir() {
			continue
		}

		info, err := e.Info()
		if err != nil {
			continue
		}

		var slot string
		var dt time.Time

		if matches := weekendPattern.FindStringSubmatch(e.Name()); matches != nil {
			slot = matches[1]
			date := matches[2]
			timeStr := saturdayTime
			if slot == "sunday" {
				timeStr = sundayTime
			}
			dt, _ = time.ParseInLocation("2006-01-02 15:04", date+" "+timeStr, loc)
		} else if matches := testPattern.FindStringSubmatch(e.Name()); matches != nil {
			slot = "test"
			date := matches[2]
			hour := matches[3]
			min := matches[4]
			dt, _ = time.ParseInLocation("2006-01-02 15:04", date+" "+hour+":"+min, loc)
		} else {
			continue
		}

		shows = append(shows, Show{
			Filename: e.Name(),
			Slot:     slot,
			DateTime: dt,
			Size:     info.Size(),
			SizeStr:  formatSize(info.Size()),
		})
	}

	sort.Slice(shows, func(i, j int) bool {
		return shows[i].DateTime.Before(shows[j].DateTime)
	})

	return shows, nil
}

func formatSize(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}

func nextWeekday(from time.Time, day time.Weekday) time.Time {
	daysUntil := int(day) - int(from.Weekday())
	if daysUntil <= 0 {
		daysUntil += 7
	}
	return from.AddDate(0, 0, daysUntil)
}

func upcomingWeekdays(from time.Time, day time.Weekday, count int) []UpcomingDate {
	dates := make([]UpcomingDate, count)
	d := nextWeekday(from, day)
	slotName := "saturday"
	if day == time.Sunday {
		slotName = "sunday"
	}
	for i := 0; i < count; i++ {
		dateStr := d.Format("2006-01-02")
		pattern := filepath.Join(showsDir, fmt.Sprintf("%s-%s.*", slotName, dateStr))
		matches, _ := filepath.Glob(pattern)
		dates[i] = UpcomingDate{
			Value:     dateStr,
			Label:     d.Format("Mon, Jan 2"),
			Scheduled: len(matches) > 0,
		}
		d = d.AddDate(0, 0, 7)
	}
	return dates
}

// API endpoint for systemd service to find today's show
func init() {
	http.HandleFunc("/api/show", func(w http.ResponseWriter, r *http.Request) {
		slot := r.URL.Query().Get("slot")
		date := r.URL.Query().Get("date")

		if slot == "" || date == "" {
			http.Error(w, "slot and date required", 400)
			return
		}

		pattern := filepath.Join(showsDir, fmt.Sprintf("%s-%s.*", slot, date))
		matches, _ := filepath.Glob(pattern)

		if len(matches) == 0 {
			http.Error(w, "no show found", 404)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"path": matches[0]})
	})
}

// unitName derives the systemd unit name from a show file path
func unitName(filePath string) string {
	base := filepath.Base(filePath)
	ext := filepath.Ext(base)
	name := strings.TrimSuffix(base, ext)
	return "radio-show-" + name
}

// scheduleShow schedules a show to stream at the given time via systemd-run
func scheduleShow(filePath string, when time.Time) error {
	unit := unitName(filePath)
	calendar := when.Format("2006-01-02 15:04:00")

	// Get icecast connection settings from environment
	icecastHost := getEnv("ICECAST_HOST", "localhost")
	icecastPort := getEnv("ICECAST_PORT", "8000")
	icecastMount := getEnv("ICECAST_MOUNT", "/stream")
	sourcePassword := os.Getenv("SOURCE_PASSWORD")

	// systemd-run creates a transient timer, pass environment to the service
	cmd := exec.Command("systemd-run",
		"--unit="+unit,
		"--on-calendar="+calendar,
		"--timer-property=AccuracySec=1s",
		"--setenv=SOURCE_PASSWORD="+sourcePassword,
		"--setenv=ICECAST_HOST="+icecastHost,
		"--setenv=ICECAST_PORT="+icecastPort,
		"--setenv=ICECAST_MOUNT="+icecastMount,
		"/usr/local/bin/stream-show.sh", filePath)

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("systemd-run failed: %v: %s", err, output)
	}
	log.Printf("Scheduled %s for %s: %s", unit, calendar, strings.TrimSpace(string(output)))
	return nil
}

// unscheduleShow cancels a scheduled show
func unscheduleShow(filename string) error {
	ext := filepath.Ext(filename)
	name := strings.TrimSuffix(filename, ext)
	unit := "radio-show-" + name

	// Stop both the timer and service (if running)
	for _, suffix := range []string{".timer", ".service"} {
		cmd := exec.Command("systemctl", "stop", unit+suffix)
		cmd.Run() // Ignore errors - unit might not exist
	}
	log.Printf("Unscheduled %s", unit)
	return nil
}

// rescheduleAllShows scans the shows directory and reschedules future shows
// Call this on startup to recover from reboots
func rescheduleAllShows() {
	shows, err := listShows()
	if err != nil {
		log.Printf("Failed to list shows for rescheduling: %v", err)
		return
	}

	now := time.Now()
	for _, show := range shows {
		if show.DateTime.After(now) {
			filePath := filepath.Join(showsDir, show.Filename)
			if err := scheduleShow(filePath, show.DateTime); err != nil {
				log.Printf("Failed to reschedule %s: %v", show.Filename, err)
			}
		}
	}
}
