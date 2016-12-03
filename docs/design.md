
## Introduction

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

Each of these is populated with its current value (or `*` if unavailable)
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

    1) Namespace Path (Namespace + Key)
    2) Context Pattern
    3) Value

For example, the following could be stored to set the default color used
when displaying the hostname portion of the user's prompt:

    ':zcfg:/prompt:*:*:*:*:*:*' user-color  Green4

This is broken down as:

| Component        | Contents             | Notes                                 |
| :-------------   | :------------------  | ------------------------------------- |
| Namespace Path   | `/prompt/user-color` | Namespace=`/prompt` Key=`user-color`  |
| Context Pattern  | `*:*:*:*:*:*`        | Matches all contexts                  |
| Value            | `Green4`             | Scalar Value                          |

See Hierarchical Namespace for details.

This value could be overridden in more specific situations -- such as, when the
user is logged into a 'production' host -- by utilizing a different Context
Pattern:

    ':zcfg:prompt:*:production:*:*' user-color  Red3

...or, if the user wants a different color while they're inside their home
directory:

    ':zcfg:prompt:*:*:*:/home/user*' user-color  DodgerBlue

Config values can reference other config values in the same namespace by
enclosing them in a "={}" sequence. See "Recursive Namespace Path Resolution"
for details.

----

## Hierarchical Namespace 

* All Zstash elements are addressed using a "Namespace Path" which is composed
  of a "Namespace" and an optional "Key".

* A Namespace is a container for Keys and/or child Namespaces

* Only Keys may have Values

* When unspecified, a default Namespace Path of "/" is assumed.
  (This represents Namespace="/" Key="")

* A single Namespace Path may refer to two distinct elements.  The path
  "/one/two" refers to both of the following:

| Namespace  |  Key   |
| :--------  | :----: |
| `/one`     | `two`  |
| `/one/two` |        |


* In the first example, the Key "two" (in Namespace "/one") may have one or
  more Values distinguished by differing context patterns.

* Simultaneously, the second Namespace (`/one/two`) may also exist as
  a container holding subsequent Values and/or Namespace Paths, such as:

| Namespace        |      Key       |
| :--------------- | :------------: |
| `/one/two`       | `BuckleMyShoe` |
| `/one/two/three` | `four`         |

NOTE: The above structure is analogous to a filesystem element that is both
a file and a directory at the same time.

----

## Recursive Namespace Path Resolution

* All zstash items are addressed using a **namespace path**.

* A namespace path appears similar to a filesystem path (e.g. `/like/this`) and
is composed of a **namespace** and a **key**.

* The **key** of a namespace path is the final path component (similar to a
  file's basename) while the **namespace** is composed of all preceding
  components (like a directory name).

EXAMPLE: Given a namespace path of `/colors/background/CornflowerBlue` the
namespace would be `/colors/background` with a key of `CornflowerBlue`.

* zstash values may reference other items using an **item reference operator**
  composed of a namespace path wrapped with braces and preceded by an equals
  sign. e.g. `={/some/namespace/path}`.

* Namespace paths are evaluated under two, distinct cases: initial and
  recursive.  *Initial* evaluation is the result of a top-level `zstash get`
  call as initiated by the user while *recursive* resolutions are performed
  by the item reference operator.

* A zstash item whose value contains an item reference operator is known as
  the *local item* while resolving the contained namespace path.

* Namespace paths come in two flavors:

    * **Full Paths**  - Those beginning with a slash (/) character. These paths
                        ignore the local item.

    * **Local Paths** - Everything else. These paths are always relative to
                        local item.

NOTE: Unlike a filesystem path, there is no concept of `.` or `..`; all
namespace paths fit into one of the above two categories as indicated by
the path's first character and the `.` character has no significant meaning
whatsoever.

* All *initial* evaluations are effectively *full path* evaluations. Since an
  initial evaluation has no current item, a default namespace of '/' is
  assumed.  Therefore, if the namespace path of an initial evaluation does not
  begin with a slash character, one will be automatically prepended.

* Recursive evaluations may be either local or full based on the first
  character of the referenced namespace path within the item reference
  operator.  Local evaluations will prepend the local item's namespace prior
  to evaluation while full evaluations will ignore it.

* Each evaluation call takes 1 or 2 parameters. The first param is always the
  namespace path to evaluate. The second is the local namespace for which this
  evaluation is taking place. If no local namespace is provided, a default,
  local namespace of '/' will be used.

----

### Evaluation Example

Assuming the following (obviously contrived) zstash items:

|  **Namespace Path**               |  **Value**                            |
|  :------------------------------  |  :----------------------------------  |
|  /labels/office                   |  "The ={location} Office"             |
|  /labels/location                 |  "Seattle, ={/offices/seattle/type}"  |
|  /offices/seattle/type            |  "={functions/engr}, Engineering"     |
|  /offices/seattle/functions/engr  |  "Commercial Middleware"              |

...a call of `zstash get /labels/office` would emit:

```
The Seattle, Commercial Middleware, Engineering Office
```
The value of `/labels/office` contains a reference to the *local path*
`location`. This item's *full path* would be `/labels/location` since its
referring item's namespace is `/labels`.

`/labels/location` makes a further reference to the *full path*
`/offices/seattle/type` so its `/labels` namespace is ignored. The value for
`/offices/seattle/type` also has a *local path* reference but this time to a
sub-namespace path `functions/engr` which resolves to
`/offices/seattle/functions/engr`.

The recursive resolution steps for `/labels/office` are:

* The ={location} Office
* The ={labels/location} Office
* The Seattle, ={/offices/seattle/type} Office
* The Seattle, ={functions/engr} Engineering Office
* The Seattle, ={/offices/seattle/functions/engr} Engineering Office
* The Seattle, Commercial Middleware Engineering Office

<!--- TODO: Add example using namespace path patterns (i.e. `/foo/*/bar`) -->
