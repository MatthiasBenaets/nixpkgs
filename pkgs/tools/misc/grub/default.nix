{ lib, stdenv, runCommand, fetchFromSavannah, fetchpatch, flex, bison, python3, autoconf, automake, libtool, bash
, rsync, gettext, ncurses, libusb-compat-0_1, freetype, qemu, lvm2, unifont, pkg-config
, buildPackages
, nixosTests
, fuse # only needed for grub-mount
, runtimeShell
, zfs ? null
, efiSupport ? false
, zfsSupport ? false
, xenSupport ? false
, kbdcompSupport ? false, ckbcomp
}:

let
  pcSystems = {
    i686-linux.target = "i386";
    x86_64-linux.target = "i386";
  };

  efiSystemsBuild = {
    i686-linux.target = "i386";
    x86_64-linux.target = "x86_64";
    armv7l-linux.target = "arm";
    aarch64-linux.target = "aarch64";
    riscv32-linux.target = "riscv32";
    riscv64-linux.target = "riscv64";
  };

  # For aarch64, we need to use '--target=aarch64-efi' when building,
  # but '--target=arm64-efi' when installing. Insanity!
  efiSystemsInstall = {
    i686-linux.target = "i386";
    x86_64-linux.target = "x86_64";
    armv7l-linux.target = "arm";
    aarch64-linux.target = "arm64";
    riscv32-linux.target = "riscv32";
    riscv64-linux.target = "riscv64";
  };

  canEfi = lib.any (system: stdenv.hostPlatform.system == system) (lib.mapAttrsToList (name: _: name) efiSystemsBuild);
  inPCSystems = lib.any (system: stdenv.hostPlatform.system == system) (lib.mapAttrsToList (name: _: name) pcSystems);

  gnulib = fetchFromSavannah {
    repo = "gnulib";
    # NOTE: keep in sync with bootstrap.conf!
    rev = "9f48fb992a3d7e96610c4ce8be969cff2d61a01b";
    hash = "sha256-mzbF66SNqcSlI+xmjpKpNMwzi13yEWoc1Fl7p4snTto=";
  };

  src = fetchFromSavannah {
    repo = "grub";
    rev = "grub-2.12-rc1";
    hash = "sha256-DrNFzi2o7ZUfL3bMdG63xivZIjcTgv8RODJz7hLJ3WY=";
  };

  # HACK: the translations are stored on a different server,
  # not versioned and not included in the git repo, so fetch them
  # and hope they don't change often
  locales = runCommand "grub-locales" {
    nativeBuildInputs = [rsync];

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-XpQ4tu5eNRARdbg95LOjqp+2RCVRj1qZWe+Sc0O5zNg=";
  }
  ''
    mkdir -p po
    ${src}/linguas.sh

    mv po $out
  '';
in (

assert efiSupport -> canEfi;
assert zfsSupport -> zfs != null;
assert !(efiSupport && xenSupport);

stdenv.mkDerivation rec {
  pname = "grub";
  version = "2.12-rc1";
  inherit src;

  patches = [
    ./fix-bash-completion.patch
    ./add-hidden-menu-entries.patch

    # Revert upstream commit that breaks reading XFS filesystems
    # FIXME: remove when fixed upstream
    (fetchpatch {
      url = "https://git.savannah.gnu.org/cgit/grub.git/patch/?id=ef7850c757fb3dd2462a512cfa0ff19c89fcc0b1";
      revert = true;
      hash = "sha256-p8Kcv9d7ri4eJU6Fgqyzdj0hV5MHSe50AF02FPDJx2Y=";
    })

    # Fixes for NTFS bugs (CVE-2023-4692 and CVE-2023-4693)
    (fetchpatch {
      url = "https://git.savannah.gnu.org/cgit/grub.git/patch/?id=43651027d24e62a7a463254165e1e46e42aecdea";
      hash = "sha256-/oudbfL8Ph7ZsgsFUI0YIddji+7okFRG12E/rDsgvNM=";
    })
    (fetchpatch {
      url = "https://git.savannah.gnu.org/cgit/grub.git/patch/?id=0ed2458cc4eff6d9a9199527e2a0b6d445802f94";
      hash = "sha256-6EhLzVapN2n62Lgo+PnB4SRvDkYWFkrKNinCvArRUXk=";
    })
    (fetchpatch {
      url = "https://git.savannah.gnu.org/cgit/grub.git/patch/?id=7e5f031a6a6a3decc2360a7b0c71abbe598e7354";
      hash = "sha256-R2vmVGidm1ZFxopt/71y2816z2i/vvPrthZE52oc4CI=";
    })
    (fetchpatch {
      url = "https://git.savannah.gnu.org/cgit/grub.git/patch/?id=7a5a116739fa6d8a625da7d6b9272c9a2462f967";
      hash = "sha256-T1LglEcUl9GXQjJ6Y4fKuFyFAujNRbcAb9KoNkl6jXs=";
    })
    (fetchpatch {
      url = "https://git.savannah.gnu.org/cgit/grub.git/patch/?id=1fe82c41e070385e273d7bb1cfb482627a3c28e8";
      hash = "sha256-x/V7bmRaNxo8NNOUwVti59n9ST/2yTJ/blWjk3omdqE=";
    })
    (fetchpatch {
      url = "https://git.savannah.gnu.org/cgit/grub.git/patch/?id=e58b870ff926415e23fc386af41ff81b2f588763";
      hash = "sha256-a0faNQafL+uRIglnILkLj64ROWxqmczQTQSu3VdklSk=";
    })
  ];

  postPatch = if kbdcompSupport then ''
    sed -i util/grub-kbdcomp.in -e 's@\bckbcomp\b@${ckbcomp}/bin/ckbcomp@'
  '' else ''
    echo '#! ${runtimeShell}' > util/grub-kbdcomp.in
    echo 'echo "Compile grub2 with { kbdcompSupport = true; } to enable support for this command."' >> util/grub-kbdcomp.in
  '';

  depsBuildBuild = [ buildPackages.stdenv.cc ];
  nativeBuildInputs = [ bison flex python3 pkg-config gettext freetype autoconf automake ];
  buildInputs = [ ncurses libusb-compat-0_1 freetype lvm2 fuse libtool bash ]
    ++ lib.optional doCheck qemu
    ++ lib.optional zfsSupport zfs;

  strictDeps = true;

  hardeningDisable = [ "all" ];

  separateDebugInfo = !xenSupport;

  preConfigure =
    '' for i in "tests/util/"*.in
       do
         sed -i "$i" -e's|/bin/bash|${stdenv.shell}|g'
       done

       # Apparently, the QEMU executable is no longer called
       # `qemu-system-i386', even on i386.
       #
       # In addition, use `-nodefaults' to avoid errors like:
       #
       #  chardev: opening backend "stdio" failed
       #  qemu: could not open serial device 'stdio': Invalid argument
       #
       # See <http://www.mail-archive.com/qemu-devel@nongnu.org/msg22775.html>.
       sed -i "tests/util/grub-shell.in" \
           -e's/qemu-system-i386/qemu-system-x86_64 -nodefaults/g'

      unset CPP # setting CPP intereferes with dependency calculation

      patchShebangs .

      GNULIB_REVISION=$(. bootstrap.conf; echo $GNULIB_REVISION)
      if [ "$GNULIB_REVISION" != ${gnulib.rev} ]; then
        echo "This version of GRUB requires a different gnulib revision!"
        echo "We have: ${gnulib.rev}"
        echo "GRUB needs: $GNULIB_REVISION"
        exit 1
      fi

      cp -f --no-preserve=mode ${locales}/* po

      ./bootstrap --no-git --gnulib-srcdir=${gnulib}

      substituteInPlace ./configure --replace '/usr/share/fonts/unifont' '${unifont}/share/fonts'
    '';

  postConfigure = ''
    # make sure .po files are up to date to workaround
    # parallel `msgmerge --update` on autogenerated .po files:
    #   https://github.com/NixOS/nixpkgs/pull/248747#issuecomment-1676301670
    make dist
  '';

  configureFlags = [
    "--enable-grub-mount" # dep of os-prober
  ] ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
    # grub doesn't do cross-compilation as usual and tries to use unprefixed
    # tools to target the host. Provide toolchain information explicitly for
    # cross builds.
    #
    # Ref: # https://github.com/buildroot/buildroot/blob/master/boot/grub2/grub2.mk#L108
    "TARGET_CC=${stdenv.cc.targetPrefix}cc"
    "TARGET_NM=${stdenv.cc.targetPrefix}nm"
    "TARGET_OBJCOPY=${stdenv.cc.targetPrefix}objcopy"
    "TARGET_RANLIB=${stdenv.cc.targetPrefix}ranlib"
    "TARGET_STRIP=${stdenv.cc.targetPrefix}strip"
  ] ++ lib.optional zfsSupport "--enable-libzfs"
    ++ lib.optionals efiSupport [ "--with-platform=efi" "--target=${efiSystemsBuild.${stdenv.hostPlatform.system}.target}" "--program-prefix=" ]
    ++ lib.optionals xenSupport [ "--with-platform=xen" "--target=${efiSystemsBuild.${stdenv.hostPlatform.system}.target}"];

  # save target that grub is compiled for
  grubTarget = if efiSupport
               then "${efiSystemsInstall.${stdenv.hostPlatform.system}.target}-efi"
               else lib.optionalString inPCSystems "${pcSystems.${stdenv.hostPlatform.system}.target}-pc";

  doCheck = false;
  enableParallelBuilding = true;

  postInstall = ''
    # Avoid a runtime reference to gcc
    sed -i $out/lib/grub/*/modinfo.sh -e "/grub_target_cppflags=/ s|'.*'|' '|"
    # just adding bash to buildInputs wasn't enough to fix the shebang
    substituteInPlace $out/lib/grub/*/modinfo.sh \
      --replace ${buildPackages.bash} "/usr/bin/bash"
  '';

  passthru.tests = {
    nixos-grub = nixosTests.grub;
    nixos-install-simple = nixosTests.installer.simple;
    nixos-install-grub-uefi = nixosTests.installer.simpleUefiGrub;
    nixos-install-grub-uefi-spec = nixosTests.installer.simpleUefiGrubSpecialisation;
  };

  meta = with lib; {
    description = "GNU GRUB, the Grand Unified Boot Loader";

    longDescription =
      '' GNU GRUB is a Multiboot boot loader. It was derived from GRUB, GRand
         Unified Bootloader, which was originally designed and implemented by
         Erich Stefan Boleyn.

         Briefly, the boot loader is the first software program that runs when a
         computer starts.  It is responsible for loading and transferring
         control to the operating system kernel software (such as the Hurd or
         the Linux).  The kernel, in turn, initializes the rest of the
         operating system (e.g., GNU).
      '';

    homepage = "https://www.gnu.org/software/grub/";

    license = licenses.gpl3Plus;

    platforms = platforms.gnu ++ platforms.linux;

    maintainers = [ maintainers.samueldr ];
  };
})
