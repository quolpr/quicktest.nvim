project('criterion', 'c', version: '2.4.1')

criterion_dep = declare_dependency( # use the build machine compiler
    dependencies: meson.get_compiler('c', native: true).find_library('criterion', dirs: meson.current_source_dir() + '/criterion-2.4.1/lib'),
    include_directories: include_directories('criterion-2.4.1/include')
)

meson.override_dependency('criterion', criterion_dep)

if not meson.is_subproject()
  example = executable('example', 'test_example.c', dependencies: criterion_dep)
  test('criterion-test', example) # run with meson test from build directory
endif
