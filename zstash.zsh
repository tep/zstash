#
# zstash - A Datastore for Zsh Setting
#
# Copyright:  (c) 2016 Timothy E. Peoples
#
#     This file is part of "zstash".
#     
#     "zstash" is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published
#     by the Free Software Foundation, either version 2 of the License,
#     or (at your option) any later version.
#     
#     "zstash" is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#     
#     You should have received a copy of the GNU General Public License
#     along with "zstash".  If not, see <http://www.gnu.org/licenses/>.
#

emulate -L zsh

zmodload zsh/pcre
zmodload zsh/zselect

autoload -Uz regexp-replace

setopt errreturn
setopt warncreateglobal

local -r me=$(basename $0)
local -r cmd="${1:-help}"

local -r CTX=':zstash:'
local -r CTXint="${CTX}_internal_"
local -r STASHFILE="${HOME}/.zsh/stash"

local -r HELP_TOKEN="\u2597\u259e\u22a3_HELP_\u22a2\u259a\u2596"

local -ra SEGMENTS=( universe namespace site env vendor os host user topic dir )

if [[ $# -gt 0 ]]; then
  shift
fi

#####  ---------------  ######################################################
#####  HERE BE DRAGONS  ######################################################
#####  ---------------  ######################################################
##
##  The following is a bit of trickery to hide all the functions that are
##  defined here so that we only expose the parts we want exposed.  This is
##  accomplished by defining the functions once (upon first execution) and
##  then hiding them at the bottom (in an "always" clause).
##  
##  Here are the details:
##  
##    1) Before any functions are defined, we first grab a list of all
##       function names that are currently known (using the keys of
##       the shell parameter $functions).
##  
##    2) After we define new functions we can then subtract the initial
##       set from the new set of function names to get a list of only
##       the newly created function names.
##  
##    3) This list is stashed into an internal zstyle context for later
##       use.
##  
##    4) At the end of execution (in the "always" clause) we use the
##       `disable` shell builtin to hide these "internal" functions
##       from the rest of the shell (note: they're still in memory
##       but are no longer callable).
##  
##    5) When this autoloaded stanza is subsequently executed, we can
##       grab the list of internal function names from the stashed zstyle
##       context and temporarily reenable them for use here and now.
##  
##    6) The "always" clause at the end will ensure they get disabled
##       again when we're done.
##
{
  local -a private_funcnames
  if zstyle -m ${CTXint} 'funcs' '*'; then
    # Re-enable previously define "local" functions
    zstyle -a ${CTXint} 'funcs' private_funcnames
    enable -f ${private_funcnames[@]}
  else
    ### BEGIN :SETUP:
    # This rather long "else" block is only executed the first time this
    # file gets called and is skipped on subsequent executions. Its purpose
    # is to:
    #   a) define all of the internal functions and
    #   b) execute some "setup" code (at the bottom so it can use the funcs)
    local -r _startfuncs_=( ${(k)functions} )

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    die() {
      local h
      zparseopts -D h=h
      print -u2 $@
      test -z "$h" || zstash::help-message
      return 1
    }

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    zstash::help-message() {
      # TODO: Figure out how to do per-command help,
      #       e.g. "zstash help set" should print a help message for the "set" command
      #       n.b. Use $HELP_TOK
      #
      # TODO: Flesh this out and make it mo-betta in the general case
      #
      print -u2                                                          \
          "USAGE: ${me} {sub-command} [command-args...]\n"               \
          "    Available commands:\n"                                    \
          "        list:    List some or all stash definitions\n"        \
          "        get:     Get one fully resolved stash value\n"        \
          "        set:     Define a stash item\n"                       \
          "        put:     Shorthand for 'set' followed by 'save'\n"    \
          "        load:    Load (replace) stash from file system\n"     \
          "        merge:   Merge stash from file system\n"              \
          "        save:    Save in-memory stash to file system\n"       \
          "        dump:    Dump raw stash definitions to stdout\n"      \
          "        diff:    Show stash differences between mem <-> fs\n" \
          "        clear:   Clear in-memory stash\n"                     \
          "        topic:   Set the current stash 'topic'"

      return 1
    }

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    zstash::set() {
      local -A args
      zparseopts -D -A args -M \
          -site:    s:=-site   \
          -env:     e:=-env    \
          -vendor:  v:=-vendor \
          -os:      o:=-os     \
          -host:    h:=-host   \
          -user:    u:=-user   \
          -topic:   t:=-topic  \
          -dir:    -directory:=-dir d:=-dir

      if [[ "$1" == "${HELP_TOKEN}" || $# -lt 2 ]]; then
        print -u2 "USAGE: zstash set [{option} value] /namespace/key value..."
        print -u2 "   Options: (values are as at time of evaluation)"
        print -u2 "      -s, --site:   Site name"
        print -u2 "      -e, --env:    Environment within a site"
        print -u2 "      -v, --vendor: The value of \$VENDOR"
        print -u2 "      -o, --os:     The value of \$OSTYPE"
        print -u2 "      -h, --host:   Current hostname"
        print -u2 "      -u, --user:   Current username"
        print -u2 "      -t, --topic:  Current topic label"
        print -u2 "      -d, --dir:    The value of \$PWD"
        return 1
      fi  

      local nspath="$1"; shift
      local ns=/${(j:/:)${${(s:/:)nspath}[1,-2]}}   # Do not quote
      local key=${${(s:/:)nspath}[-1]}              #

      local -a ctx 

      ctx=(
        ''  
        'zstash'     # TODO: Construct this from $CTX instead
        "${ns}"
      )

      local opt 
      for opt in site env vendor os host user topic dir 
      do
        ctx+=( "${${${args[--${opt}]}/#=/}:-*}" )
      done

      zstyle -- "${(j.:.)ctx[@]}" "${key}" "$@"
    }

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    zstash::put() {
      if [[ "$1" == "${HELP_TOKEN}" ]]; then
        print -u2 "USAGE: zstash put {set parameters}"
        print -u2 "   'zstash put' is shorthand for 'zstash set' followed by 'zstash save'"
        return
      fi

      zstash::set $@
      zstash::save
    }

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    zstash::get() {
      # TODO: Add a "help message" to this and all other sub-commands.
      setopt localoptions rematchpcre
      local nspath ns key

      ns="$1"
      key="$2"

      if [[ -z "$key" ]]; then
        # If only 1 arg given, parse it to get namespace and key
        nspath="$ns"
      elif [[ "$key" =~ "^/" ]]; then
        # If key begins with a slash, toss the given namespace and parse key instead
        nspath="$key"
      fi

      # if $nspath is set, we'll split it to get namespace and key
      if [[ -n "${nspath}" ]]; then
        ns=/${(j:/:)${${(s:/:)nspath}[1,-2]}}   # Do not quote
        key=${${(s:/:)nspath}[-1]}              #
      fi

      # Puke if we have neither namespace nor key
      if [[ ! ( -n "$ns" && -n "$key" ) ]]; then
        zstash::die "usage: zstash get /namespace/key"
      fi

      local -a zp
      zstyle -a ${CTXint} 'params' zp
      zp[8]="${PWD}"

      local -a ctxa
      ctxa=( '' 'zstash' "${ns}" "${zp[@]}" )  # TODO: Construct this from $CTX instead
      local ctx="${(j.:.)ctxa}"


      local val
      zstyle -s "${ctx}" "${key}" val

      if [[ -n "${ZSTASH_DEBUG}" ]]; then
        print -u2 "zstash get: namespace='${ns}' key='${key}' context='${ctx}' value='${value}'"
      fi

      if [[ -z "${val}" ]]; then
        return
      fi

      # val="${(e)val}"

      if [[ -z "${val}" ]]; then
        return
      fi

      while regexp-replace val \
        '(\=\{([^{}]++|(?1))*\})' '$(zstash::get "${ns}" "${match[2]}")'; do :; done

      if [[ -z "${val}" ]]; then
        return
      fi

      # print "${(e)val}"
      print "${val}"
    }

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    zstash::topic() {
      local topic=${1:-*}
      local -a zp
      zstyle -a ${CTXint} 'params' zp
      zp[5]="${topic}"
      zstyle -- ${CTXint} 'params' "${zp[@]}"
    }

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    # TODO(tep): Make `list` better
    #            It should be more like traversing a filesystem-ish thing
    zstash::list() {
      local -a tmp pats comps keys values out opts
      local nspath="$1"
      local ns=${(j:/:)${${(s:/:)nspath}[1,-2]}}    # Do not quote
      local key=${${(s:/:)nspath}[-1]}              #
      local p k v c

      local prev label mapkey optstr optlen=0
      local -A vmap

      if [[ -z "${ns}" && -n "${key}" ]]; then
        ns="${key}"
        key=''
      fi

      if [[ -n "${ns}" && ! ( "${ns}" =~ '^/' ) ]]; then
        ns="/${ns}"
      fi

      if [[ -n "${ZSTASH_DEBUG}" ]]; then
        print -u2 "zstash list: namespace='${ns}' key='${key}'"
      fi

      zstyle -g pats || return 1
      for p in "${(o)pats[@]}"; do
        opts=()
        comps=( ${(s.:.)p} )

        if [[ ${p} != "${CTXint}" && "${comps[1]}" == "${CTX//:/}" && ( -z "${ns}" || "${comps[2]}" == "${ns}" ) ]]; then
          for c in {3..$#SEGMENTS}; do
            if [[ "${comps[${c}]}" != '*' ]]; then
              opts+=( "${SEGMENTS[${c}]}=${comps[${c}]}" )
            fi
          done

          if [[ ${#opts} -eq 0 ]]; then
            opts=( '*' )
          fi

          optstr="${(j: :)opts}"
          if [[ ${#optstr} -gt ${optlen} ]]; then
            optlen=${#optstr}
          fi

          if [[ -n "${key}" ]]; then
            keys=( "${key}" )
          else
            zstyle -g keys "${p}" || continue
          fi

          for k in "${(o)keys[@]}"; do
            values=()
            out=()
            zstyle -g values "${p}" "${k}" || continue
            for v in "${values[@]}"; do
              out+=( "$(echo $v | sed ':a;N;$!ba;s/\n/\\\\n/g')" )
            done

            tmp=( "${comps[2]}/${k}" "${optstr}" )
            mapkey="${(j:\u02d0:)tmp}"
            vmap[${mapkey}]="${(j:\u02df:)out}"
          done
        fi
      done

      optlen=$(( optlen + 2 ))

      for k in ${(ok)vmap}; do
        tmp=( ${(s:\u02d0:)k} )
        label="${tmp[1]}"
        optstr="${tmp[2]}"

        if [[ "${label}" != "${prev}" ]]; then
          test -n "${prev}" && echo
          print "${label}"
          prev="${label}"
        fi

        if [[ "${optstr}" != "*" ]]; then
          optstr="[${optstr}]"
        fi

        values=( ${(s:\u02df:)${vmap[$k]}} )
        if [[ ${#values} -eq 1 ]]; then
          print "    ${(r:${optlen}:)optstr}    ${(qq)values[1]}"
        else
          print "    ${(r:${optlen}:)optstr}    (${(qq)values[@]})"
        fi
      done
    }

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    zstash::dump() {
      local -a pats keys vals out

      zstyle -g pats || return 1
      for p in "${(o)pats[@]}"; do
        if [[ ${p} != "${CTXint}" && "${p[1,${#CTX}]}" = "${CTX}" ]]; then
          zstyle -g keys "${p}" || return 1
          for k in "${(o)keys[@]}"; do
            zstyle -a "${p}" "${k}" vals || return 1
            out=()
            for v in "${vals[@]}"; do
              out+=( "$(echo $v | sed ':a;N;$!ba;s/\n/\\\\n/g')" )
            done
            print "zstyle ${(qq)p} ${(qq)k} ${(qq)out[@]}" || return 1
          done
        fi
      done
    }

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    zstash::save() {
      local -a pats keys vals i lock="${STASHFILE}.lock" newf="${STASHFILE}.new.$$"

      # Attempt to aquire lock
      for i in {9..0}; do
        if ln -s "${newf}" "${lock}"; then
          TRAPEXIT="rm -f '${lock}'"
          break
        fi
        zselect -t 2 # Sleep for 20ms
      done

      # Abort if no lock aquired
      if [[ $i -eq 0 ]]; then
        print -u2 "Cannot save. Unable to aquire lock: ${lock} -> ${newf}"
        unset TRAPEXIT
        return 1
      fi

      # With lock aquired, save data
      if zstash::dump > "${newf}"; then
        mv "${newf}" "${STASHFILE}" && echo "Config data persisted to ${STASHFILE}"
      else
        return 1
      fi
    }

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    zstash::merge() {
      local line

      for line in ${(o)${(f)"$(egrep '^\<zstyle\> ' ${STASHFILE})"}}
      do
        eval "${(g:e:)line}"
      done
    }

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    zstash::clear() {
      local pats
      zstyle -g pats || return 1
      for p in "${pats[@]}"; do
        if [[ "${p[1,6]}" = "${CTX}" ]]; then
          zstyle -d "${p}" || return 1
        fi
      done
    }

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    zstash::load() {
      zstash::clear && zstash::merge
    }

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    zstash::diff() {
      diff -ub "${STASHFILE}" =(zstash::dump)
    }

    #-------------------------------------------------------------------------

    # Stash newly defined function names into a zstyle context
    private_funcnames=(  ${${(k)functions}:|_startfuncs_} )
    zstyle ${CTXint} funcs "${private_funcnames[@]}"

    local host="$(print -P %M)"
    local user="$(print -P %n)"
    local topic='*'

    if [[ -f "/etc/default/hostconfig" ]]; then
      source "/etc/default/hostconfig"
    else
      HOSTCONFIG_SITE="*"
      HOSTCONFIG_ENV="*"
    fi

    local site="${HOSTCONFIG_SITE}"
    local env="${HOSTCONFIG_ENV}"

    zstyle ${CTXint} 'params' "${site}" "${env}" "${VENDOR}" "${OSTYPE}" \
        "${host}" "${user}" "${topic}" "${PWD}"

    zstash::merge
  fi ### END :SETUP:

  case ${cmd} in
    'help')  zstash::help-message ;;

    'clear') zstash::clear $@ ;;
    'diff')  zstash::diff  $@ ;;
    'dump')  zstash::dump  $@ ;;
    'get')   zstash::get   $@ ;;
    'list')  zstash::list  $@ ;;
    'ls')    zstash::list  $@ ;;
    'load')  zstash::load  $@ ;;
    'merge') zstash::merge $@ ;;
    'save')  zstash::save  $@ ;;
    'set')   zstash::set   $@ ;;
    'put')   zstash::put   $@ ;;
    'topic') zstash::topic $@ ;;
    # TODO: Add the following commands
    #       remove - delete one (or more) items
    #       fetch  - fetch values into named params (instead of issuing to stdout)
    #                {do the right thing for arrays and associations}

    *) die -h "Unknown zstash sub-command: ${cmd}" ;;
  esac
} always {
  disable -f ${private_funcnames[@]}
}

# vim: ft=zsh
