# pytoefi

**Compile Python applications into bootable EFI applications.**

`pytoefi` is an experimental toolchain that aims to transform Python applications into EFI executables and bootable media. The long-term goal is to make firmware-level application deployment as simple as building a normal executable.

Instead of manually assembling boot environments, runtimes, drivers, bootloaders, and EFI images, `pytoefi` is intended to automate the entire process.

## Status

**Early development.**

The project is currently in the prototype stage.

The command-line interface shown throughout this document does **not** exist yet and is provided only to illustrate the intended user experience.

At present, development is being performed through internal testbed scripts and automated build pipelines.

## Goals

* Build bootable EFI applications directly from Python source code.
* Additional `--keep-services` flag avoids ExitBootServices() execution. (Uses Intel's EDK II CPython port)
* Experimental `--minimal-native` flag aims for smallest possible footprint. (May break functionality; Uses Nuitka)
* GUI support coming soon in Normal mode (not available if `--keep-services` or `--minimal-native` flags are used)
* Support both MicroPython and CPython workloads where practical. (highly experimental right now)
* Generate self-contained bootable EFI applications. (static mode)
* Create bootable USB media automatically. (requires additional flags)
* Bundle required runtimes and dependencies. (static mode)
* Support machine-specific builds using Linux kernel configuration profiles.
* Minimize the amount of firmware and bootloader knowledge required from end users.

## Intended Usage

Example future workflows:

```bash
pytoefi hello.py
```

Build a basic EFI application using defaults.

```bash
pytoefi --build-static hello.py
```

Build a self-contained EFI application with bundled runtime components.

```bash
pytoefi --build-static hello.py --bootable-media:E:
```

Create bootable media containing the generated application.

```bash
pytoefi --build-static hello.py \
         --bootable-media:E: \
         --target-machine=./configs/oldpc.config
```

Build using a specific Linux kernel configuration profile.

```bash
pytoefi --build-static hello.py \
         --bootable-media:E: \
         --keep-services
```

Build a self-contained EFI application with bundled runtime components and avoid execution of ExitBootServices().

```bash
pytoefi --build-static hello.py \
         --bootable-media:E: \
         --minimal-native
```

Build a native EFI application using Nuitka.

## Machine Profiles

Machine profiles are based on Linux kernel configuration files. (not usable if `--keep-services` or `--minimal-native` flag is used) 

These profiles influence driver selection, compatibility targets, and generated boot environments.

If no profile is specified, the tool may generate a build based on the current host environment and include additional virtualization-oriented support where appropriate.

The exact behavior is still under development.


## Secure Boot

`pytoefi` does not guarantee that generated images will boot on systems with Secure Boot enabled.

Successful booting depends on factors such as:

* Secure Boot configuration.
* Available signing keys.
* Custom certificate enrollment.
* Platform firmware policies.
* Image signing setup.

Users are responsible for ensuring that generated images satisfy the requirements of their target systems.

## Current Development Focus

Current work is focused on:

* Runtime integration.
* EFI image generation.
* Boot environment construction.
* Dependency packaging.
* Automated media generation.
* Hardware compatibility.
* QEMU-based validation workflows.

## What this won't do

At this stage, the project is not intended to:

* Replace existing operating systems.
* Replace traditional firmware development toolchains.
* Guarantee compatibility with every UEFI implementation.
* Provide a stable API or command-line interface.

## License

MIT License
