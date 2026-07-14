FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
ENV CUDA_HOME=/usr/local/cuda
ENV GPU_INCLUDE_PATH=/usr/local/cuda/include
ENV GPU_LIBRARY_PATH=/usr/local/cuda/lib64
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}
# System packages
RUN apt-get update && apt-get install -y \
    build-essential \
    csh vim nano \
    git \
    wget \
    curl \
    unzip \
    pkg-config \
    ca-certificates \
    python3-setuptools \
    python3-wheel \
    libboost-all-dev \
    libeigen3-dev \
    zlib1g-dev \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Install modern CMake (Kitware)
RUN apt-get update && apt-get install -y curl gnupg ca-certificates lsb-release && \
    curl -fsSL https://apt.kitware.com/keys/kitware-archive-latest.asc | gpg --dearmor -o /usr/share/keyrings/kitware-archive-keyring.gpg && \
    chmod 644 /usr/share/keyrings/kitware-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu $(lsb_release -cs) main" > /etc/apt/sources.list.d/kitware.list && \
    apt-get update && apt-get install -y cmake && \
    rm -rf /var/lib/apt/lists/*

# Install NVIDIA cuDNN 9 (runtime for GNINA binary)
# Note: the machine-learning repo layout can vary; avoid adding it here to prevent 404.
# (cuDNN provided by base image)
# Python 3.12 setup
# Install Python 3.12 from deadsnakes PPA and make it the default `python`
RUN apt-get update && apt-get install -y software-properties-common lsb-release && \
    add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update && apt-get install -y python3.12 python3.12-dev python3.12-venv && \
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12 && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 && \
    python --version && \
    python -m pip install --upgrade pip setuptools wheel

# Python packages
RUN python -m pip install --no-cache-dir \
    numpy \
    scipy \
    pandas \
    rdkit \
    meeko \
    ringtail \
    gemmi \
    pdb2pqr \
    tqdm \
    pyyaml \
    networkx matplotlib openbabel-wheel

WORKDIR /opt

# AutoGrid

RUN git clone https://github.com/ccsb-scripps/AutoGrid.git AutoGrid

RUN cd AutoGrid && autoreconf -i && \
    mkdir Linux64 && \ 
    cd Linux64 && \
    ../configure && \
    make -j$(nproc) && \
    make install

# AutoDock-GPU (CUDA)
RUN git clone --recursive https://github.com/ccsb-scripps/AutoDock-GPU.git && \
    cd AutoDock-GPU && \
    make DEVICE=CUDA NUMWI=128 -j$(nproc)

# GNINA (prebuilt) with LD_LIBRARY_PATH wrapper
RUN mkdir -p /opt/GNINA/bin && \
    wget -qO /opt/GNINA/bin/gnina https://github.com/gnina/gnina/releases/download/v1.3.3/gnina.cuda12.8.static && \
    chmod +x /opt/GNINA/bin/gnina && \
    mv /opt/GNINA/bin/gnina /opt/GNINA/bin/gnina.real && \
    printf '%s\n' "#!/bin/bash" "export LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu:\${LD_LIBRARY_PATH}" "exec /opt/GNINA/bin/gnina.real \"\$@\"" \
        > /opt/GNINA/bin/gnina && \
    chmod +x /opt/GNINA/bin/gnina.real /opt/GNINA/bin/gnina

# UniDock
RUN mkdir -p /opt/UniDock && \
    wget -qO /tmp/unidock.tar.gz https://github.com/dptech-corp/Uni-Dock/archive/refs/tags/1.2.0.tar.gz && \
    tar -xzf /tmp/unidock.tar.gz -C /opt/UniDock --strip-components=1 && \
    rm -f /tmp/unidock.tar.gz && \
    cd /opt/UniDock/unidock && \
    cmake -B build -DCMAKE_INSTALL_PREFIX=/opt/UniDock -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DCUDAToolkit_ROOT=/usr/local/cuda . && \
    cmake --build build -j$(nproc) && \
    cmake --install build

ENV PATH="/opt/AutoDock-GPU/bin:/opt/GNINA/bin:/opt/UniDock/bin:/usr/local/bin:${PATH}"

WORKDIR /workspace

CMD ["/bin/bash"]