#!/bin/bash
## DOWNLOAD BINARIES
set -e
PATH=$(pwd)/node_modules/.bin:$PATH
if ! [ -x "$(command -v elm)" ]; then
	npm install elm@latest-0.19.3
fi
# It seems cloudflare pages comes with 0.19
if [[ $(elm --version) != "0.19.3" ]]; then
	npm install elm@latest-0.19.3
fi

## BUILD
elm make src/Main.elm --output public/elm.js --optimize

## CLEAN UP, cloudflare pages will reject the node_module size of >25mb
rm -rf node_modules
