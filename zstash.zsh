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
local -r STASHFILE="${ZSTASHFILE:-${HOME}/.zsh/stash}"

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
		zstash::make-pattern-map() {
			local sn sv p="${1}"
			local pp=( ${(s.:.)p} )
			local -A pa
			for i in {1..$#SEGMENTS}; do
				sn="${SEGMENTS[$i]}"
				sv="${pp[i]}"
				pa[${sn}]="${sv:-*}"
			done

			echo ${(pj<\0>)${(kv)pa}}
		}

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
		zstash::make-pattern-label() {
			local sn sv p="${1}"
			local pp=( ${(s.:.)p} )
			local -a pl

			for i in {3..$#SEGMENTS}; do
				sn="${SEGMENTS[$i]}"
				sv="${${pp[i]}:-*}"
				
				if [[ "${sv}" != '*' ]]; then
					pl+=( "${sn}=${(qq)sv}" )
				fi
			done
			
			if [[ $#pl -eq 0 ]]; then
				print '*'
			else
				print "[${(j< >)pl[@]}]"
			fi
		}

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    zstash::split-path-components() {
      local p="${1}"
      test "${p[1]}" = '/' || p="/${p}"
      p="${p:a}"
      local -a comp=( ${(@qs:/:)p} )
      shift comp
      echo ${(pj<\0>Q)comp[@]}
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
          "        remove:  Remove a stash item\n"                       \
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
    zstash::set zstash::remove () {         # Note: Two functions defined here
      local ma mode
      local -a hp ro
      local -A args

      test "${0}" = 'zstash::set' && mode='SET' || mode='REM'

      if [[ "${mode}" == 'REM' ]]; then
        ro=( -all a=-all )
      fi

      zparseopts -D -A args -M -- \
          "${ro[@]}"              \
          -site:    s:=-site      \
          -env:     e:=-env       \
          -vendor:  v:=-vendor    \
          -os:      o:=-os        \
          -host:    h:=-host      \
          -user:    u:=-user      \
          -topic:   t:=-topic     \
          -dir:    -directory:=-dir d:=-dir

      case "${mode}" in
        SET)
          ma=2
          hp=(
            "USAGE: zstash set [{option} value] /namespace/key value..."
            "   Options: (values are as at time of evaluation)"
          )
          ;;
        REM)
          ma=1
          hp=(
            "USAGE: zstash remove [{option} value] /namespace/key"
            "      -a, --all:    Delete all matching items"
          )
          ;;
      esac

      if [[ "$1" == "${HELP_TOKEN}" || $# -lt $ma ]]; then
        print -u2 -- "${(F)hp}"
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
      test "${nspath[1]}" = '/' || nspath="/${nspath}"
      nspath="${nspath:a}"

      local ns="${nspath:h}"
      local key="${nspath:t}"

      local -a ctx lbl=( "${nspath}" )

      ctx=(
        ''  
        'zstash'     # TODO: Construct this from $CTX instead
        "${ns}"
      )

      local opt 
      for opt in site env vendor os host user topic dir 
      do
        local ov="${args[--${opt}]}"
        ctx+=( "${ov:-*}" )

        if [[ -n "${ov}" ]]; then
          lbl+=( "[$opt='${ov}']" )
        fi
      done

      local ctxstr="${(j.:.)ctx[@]}"
      local lblstr="${(j: :)label[@]}"

      case "${mode}" in
        SET)
          zstyle -- "${ctxstr}" "${key}" "$@"
          ;;
        REM)
          local items=( ${(f)${:-"$(zstyle -L ${(b)ctxstr} ${key})"}} )

          if [[ "${#items}" -eq 0 ]]; then
            die "item not found: ${lblstr}"
          fi

          if [[ "${#items}" -gt 1 && -z "${args[--all]+1}" ]]; then
            die "multiple items match: ${lblstr} (use --all)\n$(zstash::list -p ${nspath})"
          fi

          zstyle -d "${ctxstr}" "${key}"
          local rem="$( zstyle -L ${(b)ctxstr} ${key})"

          if [[ "${#rem}" -gt 0 ]]; then
            die "item not deleted: ${lblstr}"
          fi
          ;;
      esac
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
      local nspath localns ns key
      setopt localoptions rematchpcre

      nspath="${1}"
      localns="${2:-/}"  # local-namespace defaults to '/'

      # append '/' if there isn't one
      if [[ "${localns[-1]}" != '/' ]]; then
        localns="${localns}/"
      fi

      # Prepend local-namespace if nspath is not a full path
      if [[ "${nspath[1]}" != '/' ]]; then
        nspath="${localns}${nspath}"
      fi

      ns="${nspath:h}"
      key="${nspath:t}"

      # Puke if we have neither namespace nor key
      if [[ ! ( -n "$ns" && -n "$key" ) ]]; then
        die "usage: zstash get /namespace/key"
      fi

      local -a zp
      zstyle -a ${CTXint} 'params' zp  # TODO Construct context value instead
      zp[8]="${PWD}"

      local -a ctxa
      ctxa=( '' 'zstash' "${ns}" "${zp[@]}" )  # TODO: Construct this from $CTX instead
      local ctx="${(j.:.)ctxa}"


      local val
      zstyle -s "${ctx}" "${key}" val

      if [[ -n "${ZSTASH_DEBUG}" ]]; then
        print -u2 "zstash get: namespace='${ns}' key='${key}' context='${ctx}' value='${val}'"
      fi

      if [[ -z "${val}" ]]; then
        return
      fi

      # TODO: Document how this regex works
      while regexp-replace val \
        '(\=\{([^{}]++|(?1))*\})' '$(zstash::get "${match[2]}" "${ns}")'; do :; done

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
    zstash::list() {
      local -A args
      zparseopts -D -A args -M -- \
          -help         h=-help       \
          -namespaces   n=-namespaces \
          -keys         k=-keys       \
          -values       v=-values     \
          -pathless     p=-pathless   \
          -recurse      r=-recurse

      if [[ -n "${(k)args[--help]}" ]]; then
        print -u2 \
          "USAGE zstash list {options} [namespace-path]\n"                        \
          "    Options:\n"                                                        \
          "        -h | --help        Print this help message\n"                  \
          "        -n | --namespaces  Show only namespace\n"                      \
          "        -k | --keys        Show only keys\n"                           \
          "        -v | --values      Show only values\n"                         \
          "        -p | --pathless    Do not show paths with values\n"            \
          "        -r | --recurse     Recurse to show descendant values\n"        \
          "\n"                                                                    \
          "    With no arguments, 'list' will show namespaces, keys and values\n" \
          "    for the root ('/') namespace.\n"                                   \
          "\n"                                                                    \
          "    The '-n', '-k', and '-v' flags may be combined. Note that if\n"    \
          "    all of them are specified, it's the same as specifying none\n"     \
          "    of them.\n"                                                        \
          "\n"                                                                    \
          "    The '-p' flag is used to suppress display of namespace paths\n"    \
          "    while showing values. It has no meaning with respect to\n"         \
          "    namespaces or keys.\n"                                             \
          "\n"                                                                    \
          "    The '-r' flag implies '-v' and only show values. It will also\n"   \
          "    negate '-p' so namespace paths will still be shown."

        return
      fi

      # Determine which items to display
      local -a modes=()
      () {
        local -a modenames=( namespaces keys values )
        local m

        for m in ${modenames[@]}; do
          if [[ -n "${(k)args[--${m}]}" ]]; then
            modes+=( "${m}" )
          fi
        done
        
        if [[ -z "${modes}" ]]; then
          modes=( ${modenames[@]} )
        fi
      }

      local recurse=''

      if [[ -n "${(k)args[--recurse]}" ]]; then
        recurse='yes'
        modes=( namespaces keys values )
        noglob unset args[--pathless]
      fi

      local nspath="${1}"
      test "${nspath[1]}" = '/' || nspath="/${nspath}"
      nspath="${nspath:a}"

      local ns="${nspath:h}" key="${nspath:t}" lmax=0
      local -a pats keys values out shown
      local -A pmap vmap

      zstyle -g pats || return 1
      for p in "${(o)pats[@]}"; do
        pmap=( "${(0)$(zstash::make-pattern-map ${p})}" )

        local pns="${pmap[namespace]}"

        if [[ "${pmap[universe]}" != "zstash" ||  "${pns[1]}" != '/' ]]; then
          continue
        fi

        if [[ "${pns}" == "${ns}" ]]; then
          values=()
          out=()
          local ostr="$( zstash::make-pattern-label "${p}")"
          local v=''

          if [[ ${#ostr} -gt ${lmax} ]]; then
            lmax=${#ostr}
          fi

          # zstyle -g values "${p}" "${key}" || continue

          if zstyle -g values "${p}" "${key}"; then
            for v in "${values[@]}"; do
              out+=( "$(echo $v | sed ':a;N;$!ba;s/\n/\\\\n/g')" )
            done

            vmap[${(q)ostr}]="${(pj<\0>)${(@)out}}"
          fi
        elif [[ "${pns}" == "${nspath}" ]]; then
          if [[ -n "${${:-keys}:*modes}" ]]; then
            # Show all keys (no values)
            zstyle -g keys "${p}"
            for k in "${(o)keys[@]}"; do
              local pk="${nspath}/${k}"
              if [[ -z "${pk:*shown}" ]]; then
                if [[ -n "${recurse}" ]]; then
                  zstash::list -r "${pk}"
                else
                  print -- "- ${pk}"
                fi
                shown+=( "${pk}" )
              fi
            done
          fi
        else
          if [[ -n "${${:-namespaces}:*modes}" ]]; then
            # List *immediate* child namespaces
            local -a pnsc=( "${(0)$(zstash::split-path-components "$pns")}" )    # Pattern NameSpace Components
            local -a nspc=( "${(0)$(zstash::split-path-components "$nspath")}" ) # NameSpace Path Components
            local -i pc=${#pnsc}
            local -i nc=${#nspc}
            local display=""

            if [[ "${nspath}" == "/" ]]; then
              display="/${pnsc[1]}"
            elif [[ "${pns[1,${#nspath}+1]}" == "${nspath}/" ]] && (( pc > nc)); then
              display="/${(j</>)pnsc[1,${nc}+1]}"
            fi

            if [[ -n "${display}" && -z "${display:*shown}" ]]; then
              if [[ -n "${recurse}" ]]; then
                zstash::list -r "${display}"
              else
                print "+ ${display}"
              fi
              shown+=( "${display}" )
            fi
          fi
        fi
      done

      if [[ $#vmap -eq 0 || -z "${${:-values}:*modes}" ]]; then
        return
      fi

      local lwid=$(( lmax + 2 ))

      if [[ -z "${(k)args[--pathless]}" ]]; then
        print -- "- ${nspath}"
      fi
      for ostr in ${(ok)vmap}; do
        values=( ${(0)vmap[${ostr}]} )
        ostr="${(Q)ostr}"
        print -- "    ${(r:${lwid}:)ostr} ${(qq)values[@]}"
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
      declare -g lock="${STASHFILE}.lock"
      local i newf="${STASHFILE}.new.$$"
      local -a pats keys vals

      # Attempt to aquire lock
      for i in {9..0}; do
        if ln -s "${newf}" "${lock}" 2>/dev/null; then
          TRAPEXIT () {
            if [[ -n "${lock}" && -h "${lock}" ]]; then
              rm -f "${lock}"
              test -L "${lock}" && echo "LOCK remains: ${lock}"
            fi
            unset lock >/dev/null || :
          }
          break
        fi
        zselect -t 2 || continue # Sleep for 20ms
      done

      # Abort if no lock aquired
      if [[ $i -eq 0 ]]; then
        print -u2 "Cannot save. Unable to aquire lock: ${lock} -> ${newf}"
        if [[ -n "${functions[TRAPEXIT]}" ]]; then
          unfunction TRAPEXIT
        fi
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
        if [[ "${p[1,8]}" == "${CTX}" && "${p[9,18]}" != "_internal_" ]]; then  # TODO: Derive substring index vals
          print -u2 "Deleting ${p}"
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
      diff -u "${STASHFILE}" =(zstash::dump)
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

    'init')   : ;;
    'clear')  zstash::clear  $@ ;;
    'diff')   zstash::diff   $@ ;;
    'dump')   zstash::dump   $@ ;;
    'get')    zstash::get    $@ ;;
    'list')   zstash::list   $@ ;;
    'ls')     zstash::list   $@ ;;
    'load')   zstash::load   $@ ;;
    'merge')  zstash::merge  $@ ;;
    'save')   zstash::save   $@ ;;
    'set')    zstash::set    $@ ;;
    'put')    zstash::put    $@ ;;
    'topic')  zstash::topic  $@ ;;
    'remove') zstash::remove $@ ;;
    'rm')     zstash::remove $@ ;;
    # TODO: Add the following commands
    #       fetch  - fetch values into named params (instead of issuing to stdout)
    #                {do the right thing for arrays and associations}

    *) die -h "Unknown zstash sub-command: ${cmd}" ;;
  esac
} always {
  disable -f ${private_funcnames[@]}
}

# vim: ft=zsh
