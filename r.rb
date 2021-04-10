class R < Formula
  desc "Software environment for statistical computing"
  homepage "https://www.r-project.org/"
  url "https://cran.r-project.org/src/base/R-4/R-4.0.5.tar.gz"
  #sha256 "523f27d69744a08c8f0bd5e1e6c3d89a4db29ed983388ba70963a3cd3a4a802e"
  license "GPL-2.0-or-later"

  depends_on "pkg-config" => :build
  depends_on "fontconfig"
  depends_on "freetype"
  depends_on "gcc" # for gfortran
  depends_on "gettext"
  depends_on "jpeg"
  depends_on "libpng"
  depends_on "libx11"
  depends_on "libxext"
  depends_on "libxmu"
  depends_on "libxt"
  depends_on "pcre2"
  depends_on "readline"
  depends_on "xz"
  depends_on "icu4c" => :optional
  depends_on "libtiff" => :optional
  depends_on "openblas" => :optional
  depends_on "openjdk" => :optional
  depends_on "sethrfore/r-srf/cairo-x11" => :optional
  depends_on "sethrfore/r-srf/tcl-tk-x11" => :optional
  depends_on "texinfo" => :optional

  ## Needed to preserve executable permissions on files without shebangs
  skip_clean "lib/R/bin", "lib/R/doc"

  def install
    # BLAS detection fails with Xcode 12 due to missing prototype
    # https://bugs.r-project.org/bugzilla/show_bug.cgi?id=18024
    ENV.append "CFLAGS", "-Wno-implicit-function-declaration"

    args = [
      "--prefix=#{prefix}",
      "--enable-memory-profiling",
      "--with-x", # SRF - Add X11 support (comment --without-x). Necessary for tcl-tk support.
      "--with-aqua",
      "--enable-R-shlib",
      "SED=/usr/bin/sed", # don't remember Homebrew's sed shim
    ]

    ## SRF - Add supporting flags for optional packages
    if build.with? "openblas"
      args << "--with-blas=-L#{Formula["openblas"].opt_lib} -lopenblas"
      args << "--with-lapack"
    else
      args << "--with-blas=-framework Accelerate"
      ENV.append_to_cflags "-D__ACCELERATE__" if ENV.compiler != :clang
    end

    args << if build.with? "openjdk"
      "--enable-java"
    else
      "--disable-java"
    end

    if build.with? "tcl-tk-x11"
      args << "--with-tcltk"
      args << "--with-tcl-config=#{Formula["tcl-tk-x11"].opt_lib}/tclConfig.sh"
      args << "--with-tk-config=#{Formula["tcl-tk-x11"].opt_lib}/tkConfig.sh"
    else
      args << "--without-tcltk"
    end

    args << if build.with? "cairo-x11"
      "--with-cairo"
    else
      "--without-cairo"
    end

    # Help CRAN packages find gettext and readline
    %w[gettext readline xz icu4c].each do |f|
      ENV.append "CPPFLAGS", "-I#{Formula[f].opt_include}"
      ENV.append "LDFLAGS", "-L#{Formula[f].opt_lib}"
    end

    system "./configure", *args
    system "make"
    ENV.deparallelize do
      system "make", "install"
    end

    cd "src/nmath/standalone" do
      system "make"
      ENV.deparallelize do
        system "make", "install"
      end
    end

    r_home = lib/"R"

    # make Homebrew packages discoverable for R CMD INSTALL
    inreplace r_home/"etc/Makeconf" do |s|
      s.gsub!(/^CPPFLAGS =.*/, "\\0 -I#{HOMEBREW_PREFIX}/include")
      s.gsub!(/^LDFLAGS =.*/, "\\0 -L#{HOMEBREW_PREFIX}/lib")
      s.gsub!(/.LDFLAGS =.*/, "\\0 $(LDFLAGS)")
    end

    include.install_symlink Dir[r_home/"include/*"]
    lib.install_symlink Dir[r_home/"lib/*"]

    # avoid triggering mandatory rebuilds of r when gcc is upgraded
    inreplace lib/"R/etc/Makeconf", Formula["gcc"].prefix.realpath,
                                    Formula["gcc"].opt_prefix
  end

  def post_install
    short_version =
      `#{bin}/Rscript -e 'cat(as.character(getRversion()[1,1:2]))'`.strip
    site_library = HOMEBREW_PREFIX/"lib/R/#{short_version}/site-library"
    site_library.mkpath
    ln_s site_library, lib/"R/site-library"

    ## SRf - R/X11 support deprecation notice
    opoo "Future R/X11 support deprecation notice.\nSee repository README and/or contribute to the discussion page at:\nhttps://github.com/sethrfore/homebrew-r-srf/discussions/40\n\n"
  end

  test do
    assert_equal "[1] 2", shell_output("#{bin}/Rscript -e 'print(1+1)'").chomp
    assert_equal ".dylib", shell_output("#{bin}/R CMD config DYLIB_EXT").chomp
    # assert_equal "[1] \"aqua\"", shell_output("#{bin}/Rscript -e 'library(tcltk)' -e 'tclvalue(.Tcl(\"tk windowingsystem\"))'").chomp

    system bin/"Rscript", "-e", "install.packages('gss', '.', 'https://cloud.r-project.org')"
    assert_predicate testpath/"gss/libs/gss.so", :exist?,
                     "Failed to install gss package"
  end
end
