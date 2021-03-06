#!/bin/bash

# nginx-cache-simple-crawler-functions.sh --- The functions for the
#                                             Nginx cache simple crawler.

# Copyright (C) 2012 António P. P. Almeida <appa@perusio.net>

# Author: António P. P. Almeida <appa@perusio.net>

# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

# Except as contained in this notice, the name(s) of the above copyright
# holders shall not be used in advertising or otherwise to promote the sale,
# use or other dealings in this Software without prior written authorization.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

function print_usage() {
    echo "$SCRIPTNAME <base URI> <dir> <nginx cache dir> [minutes ago] [parallel] [debug flag]"
} # print_usage

## Remove the trailing slash from a directory.
## $1: The directory name.
function trim_trailing_slash() {
    ## Remove trailing slashes.
    echo "$1" | sed 's#/$##'
} # trim_trailing_slash

CURL_PROG=$(which curl)
[ -x $CURL_PROG ] || exit 0

## Crawl a given file at a certain URI:
## $1: base URI.
## $2: The file to be crawled.
## $3: debug flag (optional).
function crawl_file() {
    local dir=$(trim_slashing_slash "$2")

    ## Print out the headers as a debug.
    [ -n $3 ] && $CURL_PROG -Is $1/${dir##*/}/$2
    ## The typical invocation where the output is dumped.
    [ -z $3 ] && $CURL_PROG -Is $1/${dir##*/}/$2 &>/dev/null
} # crawl_file

## Runs the command to purge the Nginx cache.
## $1: The directory of the files to be purged from the cache.
## $2: The nginx cache directory.
function run_cache_purge () {
    $SETUID_WRAPPER $NGINX_CACHE_PURGE_WRAPPER_CMD $1 $2
} # run_cache_purge

## Crawl all the files in parallel in a given directory.
## $1: base URI.
## $2: directory to be crawled.
## $3: the number of requests to issue in parallel.
## $4: debug flag (optional).
function crawl_directory() {
    local i nbr_files iterations rem

    ## Get the number of files.
    nbr_files=$(ls -1 "$2" | wc -l)
    ## Get the number of iterations of parallel requests.
    iterations=$(($3 / nbr_files))
    ## Get the remainder.
    rem=$(($3 % nbr_files))
    ## First we crawl the files in batches the size of the number of parallel.
    i=0
    while [ $i -lt $iterations ]; do
        find "$2" -type f -not -iregex "$EXCLUDE_PATTERN" -printf '%f\n' 2>/dev/null | xargs -I '%c' -P $3 -n 1 crawl_file $1 %c $4
        i=$((i + 1))
    done
    ## Now we do the remainder.
    find "$2" -type f -not -iregex "$EXCLUDE_PATTERN" -printf '%f\n' 2>/dev/null | xargs -I '%c' -P $rem -n 1 crawl_file $1 %c $4
} # crawl_directory

## Cleanup the cache if these files were already cache.
## $1: The directory of the files to be cached.
## $2: The Nginx cache directory.
## $3: The minutes ago that the files were modified.
function cleanup_cache() {
    local i dir time_ago
    ## Trim the trailing slash.
    dir=$(trim_slashing_slash "$1")

    for i in $(find "$1" -type f -name "cached_in_*.lock" -print); do
        ## Get the timestamp in the lock file and compare with now.
        time_ago=$(($(date '+%s') - $(cat $i)))
        ## If less than the minutes ago then it's still fresh. Jump to
        ## next iteration.
        [ $time_ago -lt $3 ] && continue
        ## Remove the lock file if it already exists.
        rm $i
        ## Purge the files from the cache.
        run_cache_purge "${dir##*/}*" $2
    done
} # cleanup_cache

## Create a "lock" file signaling that all files in this dir are cached.
## $1: the directory of the cached files.
function create_cache_lock() {
    echo date '+ %s' >> "$1"/$(printf '.cached_in_%s.lock' $(date '+ %d%b%Y-%Hh%Mm%Ss'))
} # create_cache_lock

## Add to a log when the cache priming process fails.
## $1: directory of files to be cached.
## $2: path to the log file.
function cache_warmer_log() {
    echo "Warning: $1 not cached." | ts >> $2
} # cache_warmer_log
