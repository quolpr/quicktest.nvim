project('example project', 'c',
  version : '0.1',
  default_options : ['warning_level=3'])

exe = executable(
  'test_example',
  'test_example.c',
  dependencies: dependency('criterion'),
)

test(exe.name(), exe)
