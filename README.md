# setup-chpl

A GitHub Action to install the Chapel programming language for all your CI needs.

## Usage

```yaml
- name: Install Chapel
  uses: jabraham17/setup-chpl@v1
  with:
    version: latest
```

### Example for Chapel version portabilty tests

This simple example creates a matrix job to test multiple Chapel versions, communication layers, and backends on both x86_64 and ARM architectures. You can customize the OS, versions, communication layers, and backends as needed.

```yaml
job:
  test-portability:
    strategy:
      matrix:
        os: [ubuntu-24.04, ubuntu-24.04-arm]
        version: [latest, 2.5.0]
        comm: [none, gasnet-udp]
        backend: [llvm, clang]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - name: Install Chapel
        uses: jabraham17/setup-chpl@v1
        with:
          version: ${{ matrix.version }}
          comm: ${{ matrix.comm }}
          backend: ${{ matrix.backend }}
      - name: Run tests
        run: |
          # Add your test commands here
          # e.g. `mason test`, `chplcheck`, etc.
```

## Inputs

`setup-chpl` will always install `chpl`, `chpldoc`, `chplcheck`, and `mason`. The following inputs are supported to customize the installation:

| Input   | Description        | Default  |
|---------|--------------------|----------|
| `version` | The Chapel version to install. Use `latest` for the most recent stable release. Supports all Chapel versions since `2.0.0`, but not all configurations are supported. | `latest`   |
| `comm`    | The communication layer to use. Options are `none` and `gasnet-udp`. | `none`     |
| `backend` | The backend compiler to use. Options are `llvm` and `clang`. | `llvm`     |

