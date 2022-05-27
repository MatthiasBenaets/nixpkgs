{ lib
, stdenv
, autoreconfHook
, fetchFromGitHub
, gettext
, libmaxminddb
, ncurses
, openssl
, withGeolocation ? true
}:

stdenv.mkDerivation rec {
  version = "1.5.7";
  pname = "goaccess";

  src = fetchFromGitHub {
    owner = "allinurl";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-ElDsQliB2+4X/psiavGr/bHQ1tMw7VMJroqCPMkOGOs=";
  };

  nativeBuildInputs = [
    autoreconfHook
  ];

  buildInputs = [
    ncurses
    openssl
  ] ++ lib.optionals withGeolocation [
    libmaxminddb
  ] ++ lib.optionals stdenv.isDarwin [
    gettext
  ];

  configureFlags = [
    "--enable-utf8"
    "--with-openssl"
  ] ++ lib.optionals withGeolocation [
    "--enable-geoip=mmdb"
  ];

  meta = with lib; {
    description = "Real-time web log analyzer and interactive viewer that runs in a terminal in *nix systems";
    homepage = "https://goaccess.io";
    changelog = "https://github.com/allinurl/goaccess/raw/v${version}/ChangeLog";
    license = licenses.mit;
    maintainers = with maintainers; [ ederoyd46 ];
    platforms = platforms.linux ++ platforms.darwin;
  };
}
