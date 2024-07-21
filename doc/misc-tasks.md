#Miscellaneous tasks

##major tasks
- man pages documentation
  - jailtools superscript
    - [ ] status
    - [ ] start/daemon/shell/stop
    - [ ] list
    - [ ] firewall
    - [ ] upgrade
  - configuration variables
    - [ ] toggles
    - [ ] mounts
    - [ ] firewall
  - [ ] cpDep
  - [ ] firewall
  - [ ] bridge
  - [ ] installation
- [ ] IPv6
- jailLib
  - [ ] move the bridge functions to their own module
- rename certain 'template' scripts to plain as they are no longer using templating techniques
  - [ ] startRoot
  - [ ] jailLib
  - [ ] firewall
  - [ ] jailtools
- [ ] don't allow 'dmesg' information inside jails. This is actually done with sysctl kernel.dmesg_restrict=1.
      Add a check for this option and add a warning when it is not active.
- [ ] the /proc/mount inside jails shows information on the host system. Try to find a way to mitigate this.
- [ ] DHCP to assign IPs to jails and DNS to assign names to them (or something similar)
- [ ] assign and deassign a /etc/hosts <jailName>.localhost name when networking is activated.
- [ ] object capability file descriptor/macaroon shell/awk library which will be used for privileged tasks
- [ ] privileged bus with the object capability library
- [ ] Fix the firewall library as the test firewallSU fails miserably.
- [ ] Fix the firewall calls in jailtools superscript, it greatly needs to be updated.
- bootstrap support for linux distributions
  - [ ] alpine linux
  - [ ] debian
  - [ ] ubuntu
  - [ ] gentoo
- [ ] muzzler
- [ ] jt ls -z shows false positives
- [ ] jt ls doesn't show all running jails
- [ ] make jailLib a real library by moving all global instructions in a function and calling that from
      all the accessor functions to initialize.
- [ ] Removal of the global variable 'privileged'.
        It is used to avoid constantly doing '$bb id -u' to determine
        if the process is privileged or not. Maybe we could have utils.sh
        itself set g_privileged for its own use so it doesn't need to constantly
        do a system call. One thing for certain 'privileged' should be renamed to
        'g_privileged' and it should be fixed so it's used only in utils.sh.
        Other modules would have to use utils.sh's isPrivileged function.
- [ ] Fix 'jt status' for unprivileged checks of a privileged jail
- [ ] When the file run/.isPrivileged is present, it makes an unprivileged jail start
        fail because it tries to activate the network namespace.
- [ ] Fix PID jail scanning, 'jt ls'
        (Currently we use /proc/mountinfo but the information is unreliable.
        Add JT_LOCATION and JT_JAILPID to the core jail process so it can be
        used to detect jails better. This will unfortunately mean that only
        one process will be detectable. But I'm thinking that we could use
        something like pstree -p to list all the childs of the jail PID)
        This also has the unfortunate effect of making it easier for adversaries
        to know they are in a jail. But then, due to the way linux made namespaces
        and such, it is still very trivial to know when we are in a jail or not.

##minor tasks
- [ ] copy the just built busybox binary to root->jt, this should make the 'install.sh' script obsolete.
      it should also make it clearer and simpler for the end user.
- firewall
  - [ ] in firewall rules add the special 'auto' value for the ethernet device. This will put the
        standard internet facing ethernet device automatically.


##unorganized tasks
jailtools's arguments and jail path management sucks currently, we need to handle those better.
for example, if we want to do status on an absolute jail path we have to do :
jt status /some/path/jail -p
What we would want is to do :
jt status -p /some/path/jail

send jailTools special patches to upstream busybox and make changes until they are merged.

make an awk nroff for busybox so the command 'man' can work correctly and send the patches to upstream.

make jailTools man pages documentation for all commands and concepts. asciidoc should be able to generate
man pages out of markdown.

implement jailTools applets in the Makefile (start with the dummy applet), this will be used among others for ttyController (DONE)

continue work on the network usage accounting project in jailTools
also, a quota on network usage would be interesting.
Could we also use CGROUPS to limit ressources as well?
hourly save of bandwidth should be adequate.
With a way to calculate the current actual bandwidth usage and the
live download and upload speeds.
We need ressource management stats!

We need to have a mean to support networking for unprivileged users. Proxy packets through a UDS maybe?
This would be particularly useful for child jails as setting up networking for jails inside an other
jail would be very tricky without root. But this would require iptables to set up transparently.

continue work on the ttyController part of jailTools (and it needs a lot of tests implemented)
	I'm so close of making this all work with ttyController, but there are some really stupid bugs
	left which are very hard to fix... I'm even wondering if I'm not hitting some corner cases
	of busybox.

implement INI file support for jailTools
INI just needs write support before being implemented in jt.
Convert jt to be able to support INI. This means centralizing all access to config variables through
specific functions. (DONE)

internal firewall is totally broken in jailTools, gotta fix it, that's (DONE), gotta test though

Fix a bug where it is not possible to call jt when it is only available through busybox (no PATH location)
	This is a tough bug to fix because busybox doesn't give any noticeable hints that the script is being called
	through busybox... so as stated a little further here, a redesign might be necessary to make the script
	be self sufficient without having to call itself again down the line. We can always check /proc/self/exe to see if we are busybox or not.

Maybe a redesign is necessary concerning the --show and --run of jt, look into making everything accessible from
the one executable rather than calling jt itself through jt, which is very weird when you think about it.
