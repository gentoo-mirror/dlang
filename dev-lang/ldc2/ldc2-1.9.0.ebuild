# Copyright 1999-2018 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=6

inherit multilib-build cmake-utils versionator llvm

MY_PV="$(replace_version_separator '_' '-')"
MY_P="ldc-${MY_PV}-src"
SRC_URI="https://github.com/ldc-developers/ldc/releases/download/v${MY_PV}/${MY_P}.tar.gz"
S=${WORKDIR}/${MY_P}

DESCRIPTION="LLVM D Compiler"
HOMEPAGE="https://ldc-developers.github.com/ldc"
KEYWORDS="~x86 ~amd64 ~arm"
LICENSE="BSD"
SLOT="$(get_version_component_range 1-2)/$(get_version_component_range 3)"

IUSE="static-libs"

# We support LLVM 3.7 through 6.
RDEPEND="|| (
		sys-devel/llvm:6
		sys-devel/llvm:5
		sys-devel/llvm:4
		>=sys-devel/llvm-3.7:0
	)
	<sys-devel/llvm-7:=
	>=app-eselect/eselect-dlang-20140709"
DEPEND=">=dev-util/cmake-2.8
	${RDEPEND}"
LLVM_MAX_SLOT=6
PATCHES="${FILESDIR}/ldc2-1.9.0-link-defaultlib-shared.patch"

# For now, we support amd64 multilib. Anyone is free to add more support here.
MULTILIB_COMPAT=( abi_x86_{32,64} )

DLANG_VERSION_RANGE="2.068-"
DLANG_PACKAGE_TYPE="single"

inherit dlang

detect_hardened() {
	gcc --version | grep -o Hardened
}

src_prepare() {
	cmake-utils_src_prepare
}

d_src_configure() {
	# Make sure libphobos2 is installed into ldc2's directory.
	export LIBDIR_${ABI}="${LIBDIR_HOST}"
	local mycmakeargs=(
		-DD_VERSION=2
		-DCMAKE_INSTALL_PREFIX=/opt/ldc2-$(get_version_component_range 1-2)
		-DD_COMPILER="${DMD}"
		-DD_COMPILER_DMD_COMPAT=1
	)
	use static-libs && mycmakeargs+=( -DBUILD_SHARED_LIBS=BOTH ) || mycmakeargs+=( -DBUILD_SHARED_LIBS=ON )
	use abi_x86_32 && use abi_x86_64 && mycmakeargs+=( -DMULTILIB=ON )
	detect_hardened && mycmakeargs+=( -DADDITIONAL_DEFAULT_LDC_SWITCHES=', "-relocation-model=pic"' )
	cmake-utils_src_configure
}

d_src_compile() {
	cmake-utils_src_make
}

d_src_install() {
	cmake-utils_src_install

	rm -rf "${ED}"/usr/share/bash-completion
}

pkg_postinst() {
	# Update active ldc2
	"${ROOT}"/usr/bin/eselect dlang update ldc2
}

pkg_postrm() {
	"${ROOT}"/usr/bin/eselect dlang update ldc2
}
