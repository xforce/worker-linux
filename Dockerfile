FROM ubuntu:18.04
ADD . /compat

RUN apt-get update && apt-get install -y \
	software-properties-common \
	ca-certificates \
	git \
	wget \
	ssh \ 
	pkg-config

# add toolchain repo
RUN add-apt-repository ppa:ubuntu-toolchain-r/test

# add clang repo 
RUN echo deb http://apt.llvm.org/bionic/ llvm-toolchain-bionic-7 main > /etc/apt/sources.list.d/llvm.list && wget -O - http://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add

# install compilation dependencies
RUN apt-get update && apt-get install -y \
	clang-7 \
	clang-tidy-7 \
	ninja-build \
	make \
	zsh \
	build-essential \
	curl \
	subversion \
	cmake \
	libssl-dev && \
	apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-7 100
RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-7 100
RUN update-alternatives --install /usr/bin/cc cc /usr/bin/clang 40
RUN update-alternatives --install /usr/bin/c++ c++ /usr/bin/clang++ 40
RUN update-alternatives --install /usr/bin/cpp cpp /usr/bin/clang++ 40

RUN update-alternatives --set cc /usr/bin/clang
RUN update-alternatives --set c++ /usr/bin/clang++
RUN update-alternatives --set cpp /usr/bin/clang++

# Build static OpenSSL
ENV SSL_VER=1.0.2o \
	PREFIX=/usr/local \
	PATH=/usr/local/bin:$PATH

RUN curl -sL http://www.openssl.org/source/openssl-$SSL_VER.tar.gz | tar xz && \
	cd openssl-$SSL_VER && \
	./Configure no-shared --prefix=$PREFIX --openssldir=$PREFIX/ssl no-zlib linux-x86_64 -fPIC && \
	make depend 2> /dev/null && make -j$(nproc) && make install && \
	cd .. && rm -rf openssl-$SSL_VER

ENV OPENSSL_LIB_DIR=$PREFIX/lib \
	OPENSSL_INCLUDE_DIR=$PREFIX/include \
	OPENSSL_DIR=$PREFIX \
	OPENSSL_STATIC=1

# Build libc++
ENV CXX="clang++ -fPIC -std=c++17 -I/compat -include /compat/glibc_version.h"
ENV CC="clang -fPIC -include /compat/glibc_version.h"
ENV CPP="clang -E"
ENV LINK="clang++ -L/compat"

RUN mkdir /libcpp && \
	cd /libcpp && \
	svn co http://llvm.org/svn/llvm-project/llvm/branches/release_70 llvm && \
	cd llvm/projects && \
	svn co http://llvm.org/svn/llvm-project/libcxx/branches/release_70 libcxx && \
	svn co http://llvm.org/svn/llvm-project/libcxxabi/branches/release_70 libcxxabi && \
	cd .. && \
	mkdir build && \
	cd build && \
	cmake -G "Unix Makefiles" \ 
	-DLIBCXX_ENABLE_SHARED=NO \
	-DLIBCXX_INCLUDE_BENCHMARKS=NO \
	-DLIBCXX_ENABLE_STATIC=YES \             
	-DLIBCXXABI_ENABLE_SHARED=NO \             
	-DLIBCXXABI_ENABLE_STATIC=YES \           
	-DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
	-DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=YES \
	-DCMAKE_INSTALL_PREFIX=/usr/ \
	-DCMAKE_BUILD_TYPE=Release \
	/libcpp/llvm && \
	make cxx && \
	make install-cxx install-cxxabi && \
	cp /libcpp/llvm/projects/libcxxabi/include/* /usr/include/c++/v1/ && \
	rm -rf /libcpp

ENV CXX="clang++ -fPIC -std=c++17 -stdlib=libc++ -I/compat -include /compat/glibc_version.h"

# Prepare static libs 
RUN objcopy --redefine-syms=/compat/glibc_version.redef /usr/local/lib/libssl.a /compat/libssl.a
RUN objcopy --redefine-syms=/compat/glibc_version.redef /usr/local/lib/libcrypto.a /compat/libcrypto.a

# Get breakpad symbol dumper 
RUN wget https://github.com/sbx320/binaries/blob/master/dump_syms?raw=true -O /usr/bin/dump_syms && chmod +x /usr/bin/dump_syms

RUN apt update && apt install -y \
	xorg-dev \
	libgtk-3-dev \
	libpulse-dev \
	libasound2-dev
