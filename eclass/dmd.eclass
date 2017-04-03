# @ECLASS: dmd.eclass
# @MAINTAINER: marco.leise@gmx.de
# @BLURB: Captures most of the logic for installing DMD
# @DESCRIPTION:
# Helps with the maintenance of the various DMD versions by capturing common
# logic.

if [[ ${___ECLASS_ONCE_DMD} != "recur -_+^+_- spank" ]] ; then
___ECLASS_ONCE_DMD="recur -_+^+_- spank"

if has ${EAPI:-0} 0 1 2 3 4 5; then
	die "EAPI must be >= 6 for dmd packages."
fi

DESCRIPTION="Reference compiler for the D programming language"
HOMEPAGE="http://dlang.org/"
HTML_DOCS="html/*"

# DMD supports amd64/x86 exclusively
MULTILIB_COMPAT=( abi_x86_{32,64} )

inherit multilib-build versionator

# License doesn't allow redistribution
LICENSE="DMD"
RESTRICT="mirror"

IUSE="doc examples static-libs tools"
SLOT="$(get_version_component_range 1-2)"
MAJOR="$(get_major_version)"
MINOR="$((10#$(get_version_component_range 2)))"
PATCH="$(get_version_component_range 3)"
VERSION="$(get_version_component_range 1-3)"
BETA="$(echo $(get_version_component_range 4) | cut -c 5-)"
ARCHIVE="${ARCHIVE-linux.tar.xz}"
SONAME="${SONAME-libphobos2.so.0.${MINOR}.${PATCH}}"
SONAME_SYM="$(echo ${SONAME} | cut -d. -f5 --complement)"
declare -ga FILES=(
	[1]="license.txt                license.txt"
	[2]="src/druntime/LICENSE       druntime-LICENSE.txt"
	[3]="src/druntime/README.md     druntime-README.md"
	[4]="src/phobos/LICENSE_1_0.txt phobos-LICENSE_1_0.txt"
	[5]="src/dmd/backendlicense.txt dmd-backendlicense.txt"
	[6]="src/dmd/boostlicense.txt   dmd-boostlicense.txt"
)

dmd_symlinkable() {
	# Return whether dmd will find dmd.conf in the executable directory, if we
	# call it through a symlink.
	[[ "${MAJOR}" -ge 2 ]] && [[ "${MINOR}" -ge 66 ]]
}

dmd_selfhosting() {
	# Return whether this dmd is self-hosting.
	[[ "${MAJOR}" -ge 2 ]] && [[ "${MINOR}" -ge 68 ]]
}

# Self-hosting DMD is handled as a 'dlang' package with compiler choices.
DLANG_VERSION_RANGE="${DLANG_VERSION_RANGE-${SLOT}}"
DLANG_PACKAGE_TYPE=single
dmd_selfhosting && inherit dlang

# Call EXPORT_FUNCTIONS after any imports
EXPORT_FUNCTIONS src_prepare src_compile src_test src_install pkg_postinst pkg_postrm

if [[ -n "${BETA}" ]]; then
	SRC_URI="http://downloads.dlang.org/pre-releases/${MAJOR}.x/${VERSION}/${PN}.${VERSION}-b${BETA}.linux.tar.xz"
else
	SRC_URI="mirror://aws/${YEAR}/${PN}.${PV}.${ARCHIVE}"
fi

COMMON_DEPEND="
	net-misc/curl[${MULTILIB_USEDEP}]
	>=app-eselect/eselect-dlang-20140709
	"
DEPEND="
	${COMMON_DEPEND}
	app-arch/unzip
	"
RDEPEND="
	${COMMON_DEPEND}
	!dev-lang/dmd-bin
	"
PDEPEND="tools? ( >=dev-util/dlang-tools-${PV} )"

S="${WORKDIR}/dmd2"
PREFIX="opt/${PN}-${SLOT}"
IMPORT_DIR="/${PREFIX}/import"

dmd_abi_to_model() {
	[[ "${ABI:0:5}" == "amd64" ]] && echo 64 || echo 32
}

dmd_foreach_abi() {
	for ABI in $(multilib_get_enabled_abis); do
		local MODEL=$(dmd_abi_to_model)
		einfo "  Executing ${1} in ${MODEL}-bit ..."
		"${@}"
	done
}

dmd_src_prepare() {
	# Convert line-endings of file-types that start as cr-lf and are installed later on
	for file in $( find . -name "*.txt" -o -name "*.html" -o -name "*.d" -o -name "*.di" -o -name "*.ddoc" -type f ); do
		edos2unix $file || die "Failed to convert DOS line-endings to Unix."
	done

	# Ebuild patches
	if [ -n "${PATCHES}" ]; then
		for p in "${PATCHES}"; do
			eapply "${FILESDIR}/${p}"
		done
	fi

	# Run other preparations
	declare -f dmd_src_prepare_extra > /dev/null && dmd_src_prepare_extra

	# User patches
	eapply_user
}

dmd_src_compile() {
	#Need to set PIC if GCC is hardened, otherwise users will be unable to link Phobos
	if [[ $(gcc --version | grep -o Hardened) ]]; then
		einfo "Hardened GCC detected - setting PIC"
		PIC="PIC=1"
	fi

	# A native build of dmd is used to compile the runtimes for both x86 and amd64
	# We cannot use multilib-minimal yet, as we have to be sure dmd for amd64
	# always gets build first.
	einfo "Building ${PN}..."
	[[ "${SLOT}" == "2.068" ]] && HOST_DMD="HOST_DC" || HOST_DMD="HOST_DMD"
	emake -C src/dmd -f posix.mak TARGET_CPU=X86 ${HOST_DMD}="${DMD}" RELEASE=1

	# Don't pick up /etc/dmd.conf when calling src/dmd/dmd !
	if [ ! -f src/dmd/dmd.conf ]; then
		einfo "Creating a dummy dmd.conf"
		touch src/dmd/dmd.conf || die "Could not create dummy dmd.conf"
	fi

	compile_libraries() {
		einfo 'Building druntime...'
		emake -C src/druntime -f posix.mak DMD=../dmd/dmd MODEL=${MODEL} MANIFEST= ${PIC}

		einfo 'Building Phobos 2...'
		emake -C src/phobos -f posix.mak DMD=../dmd/dmd MODEL=${MODEL} VERSION=../VERSION CUSTOM_DRUNTIME=1 ${PIC}
	}

	dmd_foreach_abi compile_libraries

	# Not needed after compilation. Would otherwise be installed as imports.
	rm -r src/phobos/etc/c/zlib
}

dmd_src_test() {
	test_hello_world() {
		src/dmd/dmd -m${MODEL} -Isrc/phobos -Isrc/druntime/import -L-Lsrc/phobos/generated/linux/release/${MODEL} samples/d/hello.d || die "Failed to build hello.d (${MODEL}-bit)"
		./hello ${MODEL}-bit || die "Failed to run test sample (${MODEL}-bit)"
		rm hello.o hello || die "Could not remove temporary files"
	}

	dmd_foreach_abi test_hello_world
}

dmd_src_install() {
	local MODEL=$(dmd_abi_to_model)

	# Licenses
	insinto ${PREFIX}
	for file in "${FILES[@]}"; do
		newins $file
	done

	# dmd.conf
	if has_multilib_profile; then
		cat > linux/bin${MODEL}/dmd.conf << EOF
[Environment]
DFLAGS=-I${IMPORT_DIR} -L--export-dynamic -defaultlib=phobos2
[Environment32]
DFLAGS=%DFLAGS% -L-L/${PREFIX}/lib32 -L-rpath -L/${PREFIX}/lib32
[Environment64]
DFLAGS=%DFLAGS% -L-L/${PREFIX}/lib64 -L-rpath -L/${PREFIX}/lib64
EOF
	elif [ "${ABI:0:5}" = "amd64" ]; then
		cat > linux/bin${MODEL}/dmd.conf << EOF
[Environment]
DFLAGS=-I${IMPORT_DIR} -L--export-dynamic -defaultlib=phobos2 -L-L/${PREFIX}/lib64 -L-rpath -L/${PREFIX}/lib64
EOF
	else
		cat > linux/bin${MODEL}/dmd.conf << EOF
[Environment]
DFLAGS=-I${IMPORT_DIR} -L--export-dynamic -defaultlib=phobos2 -L-L/${PREFIX}/lib -L-rpath -L/${PREFIX}/lib
EOF
	fi
	insinto ${PREFIX}/bin
	doins linux/bin${MODEL}/dmd.conf

	# DMD
	einfo "Installing ${PN}..."
	dmd_symlinkable && dosym "../../${PREFIX}/bin/dmd" "${ROOT}/usr/bin/dmd-${SLOT}"
	into ${PREFIX}
	dobin "src/dmd/dmd"

	# druntime
	einfo 'Installing druntime...'
	insinto ${PREFIX}
	doins -r src/druntime/import

	# Phobos 2
	einfo 'Installing Phobos 2...'
	into usr
	install_phobos_2() {
		# Copied get_libdir logic from dlang.eclass, so we can install Phobos correctly.
		if has_multilib_profile || [[ "${MODEL}" == "64" ]]; then
			local libdir="../opt/dmd-${SLOT}/lib${MODEL}"
		else
			local libdir="../opt/dmd-${SLOT}/lib"
		fi

		# Install shared lib.
		dolib.so src/phobos/generated/linux/release/${MODEL}/"${SONAME}"
		dosym "${SONAME}" /usr/"$(get_libdir)"/"${SONAME_SYM}"
		dosym ../../../usr/"$(get_libdir)"/"${SONAME}" /usr/"${libdir}"/libphobos2.so

		# Install static lib if requested.
		if use static-libs; then
			if has_multilib_profile || [[ "${MODEL}" == "64" ]]; then
				export LIBDIR_${ABI}="../opt/dmd-${SLOT}/lib${MODEL}"
			else
				export LIBDIR_${ABI}="../opt/dmd-${SLOT}/lib"
			fi
			dolib.a src/phobos/generated/linux/release/${MODEL}/libphobos2.a
		fi
	}
	dmd_foreach_abi install_phobos_2
	insinto ${PREFIX}/import
	doins -r src/phobos/{etc,std}

	# man pages, docs and samples
	insinto ${PREFIX}/man/man1
	doins man/man1/dmd.1
	insinto ${PREFIX}/man/man5
	doins man/man5/dmd.conf.5
	if use doc; then
		einstalldocs
		insinto "/usr/share/doc/${PF}/html"
		doins "${FILESDIR}/dmd-doc.png"
		make_desktop_entry "xdg-open ${ROOT}/usr/share/doc/${PF}/html/d/index.html" "DMD ${PV}" "${ROOT}/usr/share/doc/${PF}/html/dmd-doc.png" "Development"
	fi
	if use examples; then
		insinto ${PREFIX}/samples
		doins -r samples/d/*
		docompress -x ${PREFIX}/samples/
	fi
}

dmd_pkg_postinst() {
	# Update active dmd
	"${ROOT}"/usr/bin/eselect dlang update dmd

	elog "License files are in: /${PREFIX}"
	use examples && elog "Examples can be found in: /${PREFIX}/samples"
	use doc && elog "HTML documentation is in: /usr/share/doc/${PF}/html"
}

dmd_pkg_postrm() {
	"${ROOT}"/usr/bin/eselect dlang update dmd
}

fi
