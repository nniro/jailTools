# Roadmap for the version 0.4

- INI format for configuration files
  - [x] read
  - [ ] write
  - [ ] handle comments
  - [ ] tests
  - [ ] convert current config files
  - [ ] convert config.sh
- [ ] ttyController. This is used to fix an issue when starting a program as a daemon in one instance
    and then attempting to reaccess it from another instance. As is, the second instance will get a
    permission denied because the PID don't share a common root. Providing a common PID root is what
    ttyController provides. The purpose of this program is to make all processes be the child of the
    master process 1 inside the jail and thus retain the same permissions and accesses.
- [ ] per jail bandwidth stats
- [ ] rename rootCustomConfig.sh to jail.conf (internally, both will still be supported)
- [ ] rename rootDefaultConfig.sh to jailDefault.conf (internally, both will still be supported)
- [ ] remove or rename/repurpose 'update.sh'
