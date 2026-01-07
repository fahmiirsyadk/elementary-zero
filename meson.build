project(
  'elementary-zero', ['vala', 'c'],
  version: '1.0.0',
  license: 'GPL2+',
  meson_version: '>= 0.59.0',
)

gnome = import('gnome')
i18n = import('i18n')

glib = dependency('glib-2.0', version: '>=2.74')
gio = dependency('gio-2.0', version: '>=2.44')
gobject = dependency('gobject-2.0', version: '>=2.44')
gtk = dependency('gtk4', version: '>=4.10.0')
granite = dependency('granite-7', version: '>=7.7.0')
switchboard = dependency('switchboard-3', version: '>=8.0.0')
gee = dependency('gee-0.8')
libsoup = dependency('libsoup-3.0', version: '>=3.0.0')
json_glib = dependency('json-glib-1.0')

cc = meson.get_compiler('c')

conf = configuration_data()
conf.set_quoted('VERSION', meson.project_version())
conf.set_quoted('GETTEXT_PACKAGE', meson.project_name())
conf.set_quoted('GNOMELOCALEDIR', join_paths(get_option('prefix'), get_option('localedir')))
configure_file(output: 'config.h', configuration: conf)
config_h_dir = include_directories('.')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)

add_project_arguments(
  '--disable-since-check',
  language: 'vala'
)

subdir('data')
subdir('po')
subdir('src')

