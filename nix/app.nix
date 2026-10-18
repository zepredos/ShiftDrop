{ lib, python3Packages, qt6, tesseract }:
python3Packages.buildPythonApplication {
  pname = "shiftdrop";
  version = "0.2.0";
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../pyproject.toml
      (lib.fileset.fileFilter (file: file.hasExt "py") ../portable)
      ../linux/resources
    ];
  };
  pyproject = true;
  build-system = [ python3Packages.setuptools ];
  nativeBuildInputs = [ qt6.wrapQtAppsHook ];
  buildInputs = [ qt6.qtwayland ];
  dependencies = with python3Packages; [
    pyside6 pillow pillow-heif pypdfium2 python-docx reportlab striprtf
  ];
  # Nixpkgs builds the complete PySide6 distribution rather than PyPI's split wheels.
  postPatch = ''
    substituteInPlace pyproject.toml --replace-fail 'PySide6-Essentials' 'PySide6'
  '';
  dontWrapQtApps = true;
  makeWrapperArgs = [ "\${qtWrapperArgs[@]}" "--prefix PATH : ${lib.makeBinPath [ tesseract ]}" ];
  postInstall = ''
    install -Dm644 linux/resources/io.github.shiftdrop.ShiftDrop.svg \
      $out/share/icons/hicolor/scalable/apps/io.github.shiftdrop.ShiftDrop.svg
    mkdir -p $out/share/applications $out/share/dbus-1/services
    cat > $out/share/applications/io.github.shiftdrop.ShiftDrop.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=ShiftDrop
    Exec=$out/bin/shiftdrop %F
    Icon=io.github.shiftdrop.ShiftDrop
    Terminal=false
    Categories=Utility;Graphics;
    EOF
    cat > $out/share/dbus-1/services/io.github.shiftdrop.ShiftDrop.service <<EOF
    [D-BUS Service]
    Name=io.github.shiftdrop.ShiftDrop
    Exec=$out/bin/shiftdrop --background
    EOF
  '';
  pythonImportsCheck = [ "shiftdrop.engine" "shiftdrop.hyprland" ];
  meta = {
    description = "Local file conversions with a drag-and-Shift radial menu";
    platforms = lib.platforms.linux;
    mainProgram = "shiftdrop";
  };
}
