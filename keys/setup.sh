#!/usr/bin/env bash

openssl req \
	-x509 \
	-sha256 \
	-newkey rsa \
	-keyout rsakey.pem \
	-days 365 \
	-subj '/CN=test' \
	-nodes \
	-outform der \
	-out rsa.crt

# a 2nd key
openssl req \
	-x509 \
	-sha256 \
	-newkey rsa \
	-keyout rsakey2.pem \
	-days 365 \
	-subj '/CN=test2' \
	-nodes \
	-outform der \
	-out rsa2.crt
