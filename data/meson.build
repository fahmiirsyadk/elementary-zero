resource_files = files('elementary-zero.gresource.xml')
resources = gnome.compile_resources('io.github.elementary-zero', resource_files, c_name: 'resources')

desktop_file = i18n.merge_file(
  input: 'io.github.elementary-zero.desktop.in',
  output: 'io.github.elementary-zero.desktop',
  type: 'desktop',
  po_dir: '../po',
  install: true,
  install_dir: join_paths(get_option('datadir'), 'applications'),
)

appdata_file = i18n.merge_file(
  input: 'io.github.elementary-zero.metainfo.xml.in',
  output: 'io.github.elementary-zero.metainfo.xml',
  type: 'xml',
  po_dir: '../po',
  install: true,
  install_dir: join_paths(get_option('datadir'), 'metainfo'),
)

install_data(
  'icons/128/io.github.elementary-zero.svg',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', '128x128', 'apps')
)

