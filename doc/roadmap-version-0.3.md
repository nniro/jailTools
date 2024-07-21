# Roadmap for the version 0.3

Here is all the information concerning the upcoming version 0.3


##Summary

Mainly, this version will be the "removal" of the 2 main scripts in jails : startRoot.sh and jailLib.sh.
Those will be used from inside the 'jt' superscript.
It will still support a file version of the scripts, in which case 'jt' will detect and use them rather than the embedded ones.
It will however be the responsibility of the user to upgrade these files at that point.
We may make a mention when one of those differ from the current version to let the user know that they could upgrade them manually.

In order to do this, we create a fifo file in run which we call run/instrFile. This fifo
is piped into with the script (either startRoot.sh or jailLib.sh) and we can then run it with 'sh'.


##Tasks list

- [x] Remove/Convert startRoot.sh
- [x] Remove/Convert jailLib.sh
- [x] Create a generic function to create and use the fifo (in utils.sh)
- Convert all 'eval' script imports to use the new generic fifo function or just use the runner
    - [x] config.sh
    - [x] utils.sh
    - [x] startRoot.sh
    - [x] jailLib.sh
    - [x] jailtools.sh
    - [x] jailUpgrade.sh
    - [x] newJail.sh
- [x] Update jtUpgrade.sh (so it no longer upgrade startRoot and jailLib)
        This would pretty much remove the need for jtUpgrade.
- [x] Update cpDep.sh so it correctly detect jails
        (it used startRoot.sh to detect jails, it needs to use 'isValidJailPath'
        from utils.sh instead)
- [x] Update newJail.sh so it no longer copies startRoot and jailLib to new jails
- [x] Convert all tests that may access either startRoot or jailLib
- [x] Convert jailtools to use the new startRoot and use the generic
        function to call and use the fifo
- [x] Embed utils.sh into jailtools
- [x] Remove the no longer necessary firewall script import from jailtools
- [x] temporarily disable the jailtools superscript 'firewall' command.
        This will be fixed shortly after this version.

##Comments

- The new generic fifo function is not a panacea.
    A different fifo has to be created pretty much for each context just
    to make sure that nothing is already using one (race conditions).
    I'm not sure this is the best method for this but this is still
    way better than using 'eval' like before.
    And currently, the generic function supports both embedded and
    file at the same time. So the code is not heavier for supporting
    both; both are supported transparently using the same method.
