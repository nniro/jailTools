project('muzzler', 'c', default_options: [
  'prefix='+meson.source_root()+'/../usr'
  ,'buildtype=release'
  ,'optimization=s'
  ,'debug=false'
  ,'strip=true']
  ,version: '1.0.0'
  ,license: 'MIT')

add_project_arguments('-static', language: 'c')
add_project_link_arguments('-static', language: 'c')

genDefault = find_program('genDefaults.sh')

libseccomp = meson.get_compiler('c').find_library('seccomp')

presets = [
  'async'
  ,'basic'
  ,'control'
  ,'dangerous'
  ,'debug'
  ,'default'
  ,'fs'
  ,'memory'
  ,'misc'
  ,'net'
  ,'process'
  ,'security'
  ,'sysinfo'
  ,'unshare'
  ]

tmp = []
foreach preset : presets
  tmp += 'presets/' + preset
endforeach

presets=tmp

muzzler_h = custom_target('muzzler.h'
    ,input: presets
    ,output: 'muzzler.h'
    ,capture: true
    ,command: [genDefault])

genVersionHeader = find_program('genVersionHeader.sh')

version_h = custom_target('version.h'
    ,output: 'version.h'
    ,capture: true
    ,command: [genVersionHeader, meson.project_version()]
    )

executable('muzzler', ['muzzler.c', muzzler_h, version_h], dependencies: [libseccomp], install: true)
