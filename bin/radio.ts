#!/usr/bin/env node
import * as cdk from '@aws-cdk/core';
import { RadioStack } from '../lib/radio-stack';

const app = new cdk.App();
new RadioStack(app, 'RadioStack');
