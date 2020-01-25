apt-get -y update
apt-get install -y golang
export GOPATH=/home/ubuntu/go

go get -v -u github.com/hazrd/icecast-stress

nohup /home/ubuntu/go/bin/icecast-stress ${PRIVATE_IP}:8000 test 500 &