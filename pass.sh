#!/bin/bash
LC_ALL=C < /dev/urandom tr -dc '[:graph:]' 2>/dev/null | head -c 24; echo
