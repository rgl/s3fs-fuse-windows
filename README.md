# About

This builds a windows binary artifact of [s3fs-fuse](https://github.com/s3fs-fuse/s3fs-fuse).

Alternative: https://github.com/awslabs/mountpoint-s3

## Build (in a Ubuntu host)

Install the [windows-2022-uefi-amd64 vagrant box](https://github.com/rgl/windows-vagrant).

Build the `s3fs-fuse.zip` binary artifact:

```bash
vagrant up --no-destroy-on-error --provider=libvirt
ls -laF s3fs-fuse.zip
vagrant destroy -f
```
