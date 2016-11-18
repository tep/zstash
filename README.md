
# zstash - A Datastore for Zsh Setting

zstash is a persistent, context aware, hierarchical & dynamic storage
mechanism for zsh configuration settings. With it, you can devise
sophisticated schemes of settings in a simple and elegant manner that can
greatly simplify your zsh startup scripts, plugins and functions, all
without polluting the primary environment.

Here's a real world example of what zstash can do for you. I use zstash to
define what my shell prompt looks like; here's an example {TODO: include image}.
If we look at the definition for this setting, we'll see it has a somewhat
simple structure:

    ▶ zstash list /prompt/template
    /prompt/template
        *  '\n={user}@={host}={venv}:={pwd}\n[ ={lights} ] ={shLevel}={jobCnt}={pointer} '

...however, if we fetch this setting's resolved value within a given
context, we'll get something altogether different:

    ▶ zstash get /prompt/template

    %${colornum[Green4]}F%B%n%b%f@%${colornum[Orange1]}F%B%m%b%f${VENVPROMPT}:%${colornum[CornflowerBlue]}F%B%~%b%f
    [ ${PROMPT_LIGHTS} ] %(2L.%${colornum[Gold1]}F<${SHLVL}>%f .)%(1j.%B%${colornum[Red1]}F(%j)%f%b .)%B%(#.⭆.▶)%b 

In the sections below, we'll walk through how this seemingly simple setting
results in a rich and dynamic user explerience.

zstash is Hierarchical

    Each setting is stored using a namespace path and a key. Namespace
    segments and the settings key are specified using a slash delimited
    string which, together, appear like a familiar file path. For example,
    the setting defined with a namespace path of:

        /colors/prompt/primary/hostname

    ...would have a key of 'hostname' in the '/colors/prompt/primary'
    namespace.

    The hierarchical power of zstash is that settings need not be defined
    with a static path; you can instead define settings using a namespace
    pattern.  The setting above could instead be defined as:

        /colors/prompt/*/hostname

    ...or even:

        /colors/*/hostname

    You can still fetch its value using our original path:

        zstash get /colors/prompt/primary/hostname

    however, since the setting's namespace is defined with a pattern, you
    could also fetch '/colors/prompt/alternate/hostname' or (using the second
    pattern) '/colors/my-custom/thing/hostname' and still get the same value.

zstash is Context Aware

    In addition to its hierarchical namespace, zstash uses the shell's
    current context each time you fetch a settings value. The following
    attributes are referenced on each fetch operation:

        namespace:    Discussed above
        site:         A designation for all hosts at a given site
        env:          A designation for a subset of hosts (dev, prod, etc...)
        vendor:       The value of the zsh param $VENDOR
        ostype:       The value of the zsh param $OSTYPE
        hostname:     Current hostname
        username:     Current Username
        topic:        A user-defined label for common context
        directory:    The current working directory ($PWD)

    Using these context attributes, you can override particular settings in
    specific situations.

    For example, let's say you want the hostname portion of your prompt to
    normally be green but, except when you're logged into a production
    machine, where red would be more useful. To do this you could define
    the default setting like we did above:

        zstash set /colors/prompt/*/hostname green

    ...and then define an override setting for production hosts:

        zstash set --env=prod /colors/prompt/*/hostname red

TODO: Finish This (and move it to a README.md or similar)
zstash is Dyanmic
  {Explain recursive value resolution using ={} references}
zstash is Persistent
  {Explain persistence as text for use across multiple sites using a single repo}

