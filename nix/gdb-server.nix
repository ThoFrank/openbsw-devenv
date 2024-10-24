{ stdenv
, requireFile
, ncurses5
, unzip
, lib
, libusb-compat-0_1
, bash
}:
stdenv.mkDerivation rec{
  pname = "pegdbserver_console";
  version = "9.39.00.00";

  src = requireFile {
    name = "com.pemicro.debug.gdbjtag.pne.updatesite-5.7.8-SNAPSHOT.zip";
    sha256 = "018dk1kakykw458bagvvihhk7sd3pjb1s36cgbyawk9lkvskb0lj";
    url = "https://www.pemicro.com/products/product_viewDetails.cfm?product_id=15320151&productTab=1000000";
  };

  buildInputs = [
    ncurses5
  ];

  propagatedBuildInputs = [
    libusb-compat-0_1
  ];

  unpackPhase = ''
    ${unzip}/bin/unzip ${src} -d .
  '';

  installPhase = ''
    mkdir -p $out/bin
    ${unzip}/bin/unzip plugins/com.pemicro.debug.gdbjtag.pne_5.7.8.202404031741.jar -d $out
    unameOut="$(uname -s)"
    case "$unameOut" in
        Linux*)     os=lin;;
        Darwin*)    os=osx;;
        *)          echo "machine type '$unameOut' is not supported";exit -1
    esac

    # Mac version requires to be started with the complete path:
    # https://www.pemicro.com/forums/forum_topic.cfm?forum_id=8&forum_topic_id=8097
    chmod +x $out/$os/pegdbserver_console
    cat << EOF > $out/bin/pegdbserver_console
    #!${bash}/bin/bash
    $out/$os/pegdbserver_console \$@
    EOF
    chmod +x $out/bin/pegdbserver_console
  '';

  preFixup =
    let
      libPath = lib.makeLibraryPath [
        ncurses5
        libusb-compat-0_1
      ];
    in
    if stdenv.isLinux then
      ''
        patchelf \
          --add-needed libusb-0.1.so.4 \
          --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
          --set-rpath "${libPath}" \
          $out/lin/pegdbserver_console
      '' else "";
  meta = with lib; {
    description = "GDB server for NXP boards";
    homepage = "https://www.pemicro.com/products/product_viewDetails.cfm?product_id=15320151";
    changelog = "https://www.pemicro.com/products/product_viewDetails.cfm?product_id=15320151&productTab=1000001";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    # license = licenses.unfree;
    maintainers = [{
      name = "Thomas Frank";
      email = "thomas.frank@esrlabs.com";
      github = "ThoFrank";
    }];
    platforms = [ "x86_64-darwin" "x86_64-linux" ];
    mainProgram = "pegdbserver_console";
  };
}
