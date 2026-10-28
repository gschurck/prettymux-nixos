# NixOS package. Build: nix-build -E 'with import <nixpkgs> {}; callPackage ./nix/package.nix {}'
{
  lib,
  stdenv,
  callPackage,
  zig_0_17,
  git,
  meson,
  ninja,
  pkg-config,
  ncurses,
  wrapGAppsHook4,
  gtk4,
  libadwaita,
  json-glib,
  xdg-utils,
  bzip2,
  expat,
  fontconfig,
  freetype,
  glslang,
  harfbuzz,
  libGL,
  libpng,
  libxml2,
  oniguruma,
  simdutf,
  spirv-cross,
  zlib,
}:
let
  # Same pin as GHOSTTY_REF in .github/workflows/release.yml.
  ghosttySrc = builtins.fetchTarball {
    url = "https://github.com/patcito/ghostty/archive/bd604e89a70455c99ecc7ed38a6ffe16c20a8871.tar.gz";
    sha256 = "sha256-WKHv9Bz9Nq5brr1R7soUkc20dLelPPTQdTmflxENp3A=";
  };

  libghostty = stdenv.mkDerivation (finalAttrs: {
    pname = "libghostty";
    version = "0-unstable-bd604e8";
    src = ghosttySrc;

    # Zig can't fetch in the sandbox; the fork ships its deps as a zon2nix file.
    deps = callPackage "${ghosttySrc}/build.zig.zon.nix" { name = "libghostty-cache"; };

    nativeBuildInputs = [ zig_0_17 git ncurses pkg-config ];
    buildInputs = [
      bzip2 expat fontconfig freetype glslang harfbuzz libGL
      libpng libxml2 oniguruma simdutf spirv-cross zlib
    ];

    dontSetZigDefaultFlags = true;
    zigBuildFlags = [
      "--system" "${finalAttrs.deps}"
      "-Dapp-runtime=none"
      "-Demit-themes=true"
      "-Demit-docs=false"
      "-Doptimize=ReleaseFast"
      "-Dcpu=baseline"
    ];

    # prettymux's meson expects <ghostty_dir>/zig-out/lib.
    postInstall = "mkdir -p $out/zig-out && ln -s $out/lib $out/zig-out/lib";
  });
in
stdenv.mkDerivation {
  pname = "prettymux";
  version = "0.2.62";
  src = lib.cleanSource ../.;
  sourceRoot = "source/src/gtk";

  # The sources fall back to FHS paths that don't exist on NixOS.
  postPatch = ''
    substituteInPlace main.c \
      --replace-fail /usr/share/prettymux $out/share/prettymux \
      --replace-fail /usr/share/ghostty ${libghostty}/share/ghostty
    substituteInPlace app_support.c \
      --replace-fail /usr/share/applications $out/share/applications
    substituteInPlace bin/xdg-open prettymux-shell-integration.sh \
      --replace-fail /usr/bin/xdg-open ${xdg-utils}/bin/xdg-open
  '';

  nativeBuildInputs = [ meson ninja pkg-config wrapGAppsHook4 ];
  buildInputs = [ gtk4 libadwaita json-glib ];
  mesonFlags = [ "-Dghostty_dir=${libghostty}" ];
  # shortcut: 3 tests segfault without a display instead of skipping; run
  # `meson test` in nix-shell, re-enable once they skip headlessly.
  doCheck = false;
  passthru = { inherit libghostty; };

  # Same layout as packaging/PKGBUILD, under $out instead of /usr.
  postInstall = ''
    d=$out/share/prettymux
    mkdir -p $out/lib/prettymux $d
    ln -s ${libghostty}/lib/libghostty.so $out/lib/prettymux/libghostty.so
    install -Dm644 ../prettymux-shell-integration.sh $d/shell-integration.sh
    install -Dm644 ../prettymux-bashrc.sh $d/prettymux-bashrc.sh
    install -Dm755 -t $d/bin ../bin/open ../bin/xdg-open
    ln -s ${libghostty}/share/ghostty/shell-integration $d/shell-integration
    ln -s ${libghostty}/share/ghostty/themes $d/themes
    bash ${../packaging/verify-shell-integration.sh} $d

    # One launcher entry, named after the app id. DBusActivatable needs the
    # D-Bus service only the Flatpak ships, so launch through Exec instead.
    rm $out/share/applications/prettymux.desktop
    substituteInPlace $out/share/applications/dev.prettymux.app.desktop \
      --replace-fail $'DBusActivatable=true\n' "" \
      --replace-fail Icon=dev.prettymux.app Icon=prettymux
  '';

  meta = {
    description = "GPU-accelerated terminal multiplexer";
    homepage = "https://github.com/patcito/prettymux";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "prettymux";
  };
}
