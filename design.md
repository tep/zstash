
Stash data is stored via `zstyle` using a context pattern format of:

  :zstash:{namespace}:{site}:{environ}:{vendor}:{os}:{host}:{user}:{topic}:{directory}

Each of these components is defined as:

    zcfg         - The literal string "zcfg"
    
    {namespace}  - A namespace for this config data
                   (hierachies are specified with '/' similar to a file system)
    
    {site}       - A site specific name.
                   Usually, all hosts at a location or company
                   would share a "site" name
    
    {env}        - An environment within a site
                   (e.g. 'production', 'staging', 'office', etc...)
    
    {vendor}     - The value of ${VENDOR}

    {os}         - The value of ${OSTYPE}

    {host}       - The current hostname

    {user}       - The current username

    {topic}      - An arbitrary label used to identify a common
                   context across disparate namespaces. (e.g.,
                   when you're in a virtual environment or working
                   within a git repository)

    {dir}        - This is the current location at time of
                   evaluation (i.e. $PWD)

Each of these is populated with its current value (or '*' if unavailable)
every time a config item is fetched.

For example, given a user's session with the following current conditions:

    Username:         dave
    Hostname:         tna2.acme.com
    Directory:        /projects/awesome-sauce
    Site Name:        acme
    Environment:      test
    Operating System: linux
    Vendor:           ubuntu
    Current Topic:    {unset}

If Dave were to fetch the stashed value having a namespace path of
"/foo/bar", the zstyle "context" used for this retrieval would be:

  :zstash:/foo:acme:test:ubuntu:linux-gnu:tna2.acme.com:dave:*:/projects/awesome-sauce bar

Config data is stored using three components:

    1) context pattern
    2) name
    3) value

For example, the following could be stored to set the default color used
when displaying the hostname portion of the user's prompt:

    ':zcfg:prompt:*:*:*:*:*:*' host-color  Green4

This could then be overridden in more specific situations -- such as,
when the user is logged into a 'production' host:

    ':zcfg:prompt:*:production:*:*' user-color  Red3

...or, wants a different color while they're inside their home directory:

    ':zcfg:prompt:*:*:*:/home/user*' user-color  DodgerBlue

TODO: Update This:  =() isn't a thing anymore; we always do ${(e)...} now.

If a config value contains the sequence "=(xxx)" then the enclosed 'xxx'
will be evaluated as a shell command upon retrieval (similar to $() for
shell parameter).

Also, config values can reference other config values in the same
namespace by enclosing them in a "={}" sequence.

For example, if a user were to define the "host" segment of their prompt
like so:

    ':zcfg:prompt:*:*:*:*:*:*' host-segment '%B%F${cmap[={host-color}]}%f%b'

