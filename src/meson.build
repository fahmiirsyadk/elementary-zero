vapi_sources = [
  'config.vapi',
]

elementary_zero_vala_sources = [
  'main.vala',
  'Application.vala',
  'MainWindow.vala',
  'Widgets/BasePane.vala',
  'Widgets/Categories.vala',
  'Widgets/InstallDialog.vala',
  'Panes/RecipePane.vala',
  'Panes/EmptyPane.vala',
  'Models/Recipe.vala',
  'Services/RecipeManager.vala',
  'Services/BuildService.vala',
  'Services/InstallService.vala',
  'Services/VersionService.vala',
  'Services/StateManager.vala',
  'Services/PatchService.vala',
  'Services/RecipeValidator.vala',
  'Services/RecipeDownloader.vala',
]

elementary_zero_sources = [
  vapi_sources,
  elementary_zero_vala_sources,
  resources
]

elementary_zero_vala_args = [
  '--target-glib', '2.74',
  '--vapidir', meson.current_source_dir(),
  '--gresources', resource_files,
]

elementary_zero_c_args = [
  '-include', 'config.h'
]

elementary_zero_dependencies = [
  glib,
  gio,
  gobject,
  gtk,
  granite,
  switchboard,
  gee,
  libsoup,
  json_glib
]

executable('io.github.elementary-zero', elementary_zero_sources,
  include_directories: config_h_dir,
  vala_args: elementary_zero_vala_args,
  c_args: elementary_zero_c_args,
  dependencies: elementary_zero_dependencies,
  export_dynamic: true,
  install: true
)

