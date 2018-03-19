#!/usr/bin/env bash
#
# Wechaty - Connect ChatBots
#
# https://github.com/wechaty/wechaty
#
set -e

HOME=/bot
PATH=$PATH:/wechaty/bin:/wechaty/node_modules/.bin

function wechaty::banner() {
  echo
  figlet " Wechaty "
  echo ____________________________________________________
  echo "            https://www.chatie.io"
}

function wechaty::errorBotNotFound() {
  local file=$1
  echo "Container ERROR: can not found bot file: $HOME/$file"

  echo "Container PWD: $(pwd)"
  echo "Container HOME: $HOME"
  echo "Container LS $HOME: $(ls -l $HOME)"

  figlet " Troubleshooting "
  cat <<'TROUBLESHOOTING'

    Troubleshooting:

    1. Did you bind the current directory into container?

      check your `docker run ...` command, if there's no `volumn` arg,
      then you need to add it so that we can bind the volume of /bot:

        `--volume="$(pwd)":/bot`

      this will let the container visit your current directory.

    2. Are you sure your .js/.ts files aren't .js.txt/.ts.txt?

      this could be a problem on new Windows installs (file
      extensions hidden by default).

    if you still have issue, please have a look at
      https://github.com/chatie/wechaty/issues/66
      and do a search in issues, that might be help.

TROUBLESHOOTING
}

function wechaty::errorCtrlC() {
  # http://www.tldp.org/LDP/abs/html/exitcodes.html
  # 130 Script terminated by Control-C  Ctl-C Control-C is fatal error signal 2, (130 = 128 + 2, see above)
  echo ' Script terminated by Control-C '
  figlet ' Ctrl + C '
}

function wechaty::pressEnterToContinue() {
  local -i timeoutSecond=${1:-30}
  local message=${2:-'Press ENTER to continue ... '}

  read -r -t "$timeoutSecond"  -p "$message" || true
  echo
}

function wechaty::diagnose() {
  local -i ret=$1  && shift
  local file=$1 && shift

: echo " exit code $ret "
  figlet ' BUG REPORT '
  wechaty::pressEnterToContinue 30

  echo
  echo "### 1. source code of $file"
  echo
  cat "$HOME/$file" || echo "ERROR: file not found"
  echo

  echo
  echo "### 2. directory structor of $HOME"
  echo
  ls -l "$HOME"

  echo
  echo '### 3. package.json'
  echo
  cat "$HOME"/package.json || echo "No package.json"

  echo
  echo "### 4. directory structor inside $HOME/node_modules"
  echo
  ls "$HOME"/node_modules || echo "No node_modules"

  echo
  echo '### 5. wechaty doctor'
  echo
  wechaty-doctor

  figlet " Submit a ISSUE "
  echo _____________________________________________________________
  echo '####### please paste all the above diagnose messages #######'
  echo
  echo 'Wechaty Issue https://github.com/chatie/wechaty/issues'
  echo

  wechaty::pressEnterToContinue
}

function wechaty::runBot() {
  local botFile=$1

  if [ ! -f "$HOME/$botFile" ]; then
    wechaty::errorBotNotFound "$botFile"
    return 1
  fi

  echo  "Working directory: $HOME"
  cd    "$HOME"

  [ -f package.json ] && {
    # echo "Install dependencies modules ..."

    #
    # NPM module install will have problem in China.
    # i.e. chromedriver need to visit a google host to download binarys.
    #
    echo "Please make sure you had installed all the NPM modules which is depended on your bot script."
    # yarn < /dev/null || return $? # yarn will close stdin??? cause `read` command fail after yarn

  }

  # echo -n "Linking Wechaty module to bot ... "
  # npm link wechaty < /dev/null > /dev/null 2>&1
  # echo "linked. "

  # npm --progress=false install @types/node > /dev/null

  local -i ret=0
  case "$botFile" in
    *.js)
      if [ "$NODE_ENV" != "production" ]; then
        echo "Executing babel-node --presets env $*"
        # https://stackoverflow.com/a/34025957/1123955
        BABEL_DISABLE_CACHE=1 babel-node --presets env "$@" &
      else
        echo "Executing node $*"
        node "$@" &
      fi
      ;;
    *.ts)
      # yarn add @types/node
      echo "Executing ts-node $*"
      ts-node --type-check "$@" &
      ;;
    *)
      echo "ERROR: wechaty::runBot() neith .js nor .ts"
      exit -1 &
  esac

  wait "$!" || ret=$? # fix `can only `return' from a function or sourced script` error

  case "$ret" in
    0)
      ;;
    130)
      wechaty::errorCtrlC
      ;;
    *)
      wechaty::diagnose "$ret" "$@"
      ;;
  esac

  return "$ret"
}

function wechaty::io-client() {
  figlet " Chatie.io "
  figlet " Authing By:"
  echo
  echo "WECHATY_TOKEN=$WECHATY_TOKEN "
  echo

  npm run io-client
}

function wechaty::help() {
  figlet " Docker Usage: "
  cat <<HELP



  Usage: wechaty [ mybot.js | mybot.ts | COMMAND ]

  Run a JavaScript/TypeScript <Bot File>, or a <Wechaty Command>.

  <Bot File>:
    mybot.js: a JavaScript program for your bot. will run by Node.js v7
    mybot.ts: a TypeScript program for your bot. will run by ts-node/TypeScript v2

  <Commands>:
    demo    Run Wechaty DEMO
    doctor  Print Diagnose Report
    test    Run Unit Test

  Learn more at:
    https://github.com/chatie/wechaty/wiki/Docker



HELP
}

function main() {
  # issue #84
  echo -e 'nameserver 114.114.114.114\nnameserver 114.114.115.115' | sudo tee -a /etc/resolv.conf > /dev/null

  wechaty::banner
  figlet Connecting
  figlet ChatBots

  VERSION=$(WECHATY_LOG=WARN wechaty-version 2>/dev/null || echo '0.0.0(unknown)')

  echo
  echo -n "Starting Wechaty v$VERSION with "
  echo -n "Node.js $(node --version) ..."
  echo

  local -i ret=0

  local defaultArg=help
  if [ -n "$WECHATY_TOKEN" ]; then
    defaultArg=io-client
  fi

  case "${1:-${defaultArg}}" in
    #
    # 1. Get a shell
    #
    shell | sh | bash)
      /bin/bash -s || ret=$?
      ;;

    #
    # 2. Run a bot
    #
    *.ts | *.js)
      # set -e will not work inside wechaty::runBot because of
      # http://stackoverflow.com/a/4073372/1123955
      wechaty::runBot "$@" || ret=$?
      ;;

    #
    # 3. If there's additional `npm` arg...
    #
    npm)
      shift
      npm "$@" || ret=$?
      ;;

    help|version)
      wechaty::help
      ;;

    io-client)
      wechaty::io-client
      ;;

    test)
      # WECHATY_LOG=silent npm run test:unit
      WECHATY_LOG=silent npm run test
      ;;

    #
    # 4. Default to execute npm run ...
    #
    *)
      [ "$1" = "run" ] && shift
      npm run "$@" || ret=$?
     ;;
  esac

  wechaty::banner
  figlet " Exit $ret "
  return $ret
}

main "$@"

