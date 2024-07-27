# Sample project for the Criterion adapter

## Requirements
* `meson`
* `ninja`
* (`criterion` is bundled in the sample project)

## Setup project
```bash
# quicktest.nvim/tests/support/criterion
$ meson setup build
```
The `criterion` adapter can now be tested for this sample project, but note that the working directory is important:

Normally it is expected that the build directory is at the project root.

However, for development the working directory will typically be the root of `quicktest.nvim`.
If so then you could temporarily update the adapters's `builddir` field to point to `tests/support/criterion/build`.

## Developer notes
### Locate the test executable
For this adapter to work it needs to know which executable that contains the tests under the cursor. This is done using the `meson introspect` command which returns a json document with information on all build targets. The adapter loops through all `sources` to find a file that matches the path of the currently open buffer. The respective executable is `filename`.

**NOTE** It's possible that a project has defined multiple test executables that contains the same test source file. This is currently not handled by this adapter. Reach out if this is needed.
```bash
$:~/.local/share/nvim/lazy/quicktest.nvim/tests/support/criterion$ meson introspect --targets build | jq
[
  {
    "name": "test_example",
    "id": "test_example@exe",
    "type": "executable",
    "defined_in": "/home/derp/.local/share/nvim/lazy/quicktest.nvim/tests/support/criterion/meson.build",
    "filename": [
      "/home/derp/.local/share/nvim/lazy/quicktest.nvim/tests/support/criterion/build/test_example"
    ],
    "build_by_default": true,
    "target_sources": [
      {
        "language": "c",
        "compiler": [
          "cc"
        ],
        "parameters": [
          "-I/home/derp/.local/share/nvim/lazy/quicktest.nvim/tests/support/criterion/build/test_example.p",
          "-I/home/derp/.local/share/nvim/lazy/quicktest.nvim/tests/support/criterion/build",
          "-I/home/derp/.local/share/nvim/lazy/quicktest.nvim/tests/support/criterion",
          "-I/home/derp/.local/share/nvim/lazy/quicktest.nvim/tests/support/criterion/subprojects/criterion/criterion-2.4.1/include",
          "-fdiagnostics-color=always",
          "-D_FILE_OFFSET_BITS=64",
          "-Wall",
          "-Winvalid-pch",
          "-Wextra",
          "-Wpedantic",
          "-O0",
          "-g"
        ],
        "sources": [
          "/home/derp/.local/share/nvim/lazy/quicktest.nvim/tests/support/criterion/test_example.c"
        ],
        "generated_sources": []
      }
    ],
    "extra_files": [],
    "subproject": null,
    "installed": false
  }
]
```

### Sample test output
Example command line used by the adapter when running a single test under the cursor:
```bash
$ ./build/test_example --filter=ts_example/test_sum_basic --json
{
  "id": "Criterion v2.4.1",
  "passed": 1,
  "failed": 0,
  "errored": 0,
  "skipped": 1,
  "test_suites": [
    {
      "name": "ts_example",
      "passed": 1,
      "failed": 0,
      "errored": 0,
      "skipped": 1,
      "tests": [
        {
          "name": "test_sum_basic",
          "assertions": 0,
          "status": "PASSED"
        },
        {
          "name": "test_sum_parameterized",
          "assertions": 0,
          "status": "SKIPPED",
          "messages": ["The test was skipped."]
        }
      ]
    }
  ]
}
```

