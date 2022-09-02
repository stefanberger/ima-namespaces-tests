/* SPDX-License-Identifier: BSD-2-Clause */

#include <string.h>
#include <unistd.h>
#include <limits.h>
#include <stdlib.h>
#include <stdio.h>
#include <getopt.h>
#include <fcntl.h>
#include <errno.h>
#include <stdbool.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>

#include <linux/vtpm_proxy.h>

#ifndef VTPM_PROXY_IOC_CONNECT_TO_IMA_NS
#define VTPM_PROXY_IOC_CONNECT_TO_IMA_NS  _IO(0xa1, 0x10)
#endif

#define FLAG_CREATE_TPM2_DEVICE		(1 << 0)
#define FLAG_CREATE_TPM12_DEVICE	(1 << 1)
#define FLAG_CONNECT_TO_IMA_NS		(1 << 2)

static char *find_file_in_path(const char *fn)
{
    char pathname[PATH_MAX];
    struct stat statbuf;
    char *orig_path, *path, *p, *ret = NULL;
    int n;

    path = orig_path = strdup(getenv("PATH"));

    p = "./";
    while (p) {
        snprintf(pathname, sizeof(pathname), "%s/%s", p, fn);

        n = stat(pathname, &statbuf);
        if (n == 0) {
            ret = strdup(pathname);
            break;
        }

        p = strsep(&path, ":");
    }

    free(orig_path);

    return ret;
}

static int vtpm_proxy_create_dev(bool tpm2)
{
    struct vtpm_proxy_new_dev newdev = {
        .flags = tpm2 ? VTPM_PROXY_FLAG_TPM2 : 0,
    };
    int fd, n;
    char buffer[16];

    fd = open("/dev/vtpmx", O_RDWR);
    if (fd < 0) {
        fprintf(stderr, "Could not open /dev/vtpmx: %s\n", strerror(errno));
        return 1;
    }

    n = ioctl(fd, VTPM_PROXY_IOC_NEW_DEV, &newdev);
    close(fd);
    if (n < 0) {
        fprintf(stderr, "ioctl on /dev/vtpmx failed: %s\n", strerror(errno));
        return 1;
    }
    snprintf(buffer, sizeof(buffer), "%u", newdev.tpm_num);
    setenv("VTPM_DEVICE_NUM", buffer, 1);

    snprintf(buffer, sizeof(buffer), "%u", newdev.major);
    setenv("VTPM_DEVICE_MINOR", buffer, 1);

    snprintf(buffer, sizeof(buffer), "%u", newdev.minor);
    setenv("VTPM_DEVICE_MAJOR", buffer, 1);

    // keep fd open!
    snprintf(buffer, sizeof(buffer), "%u", newdev.fd);
    setenv("VTPM_DEVICE_FD", buffer, 1);

    return 0;
}

static int vtpm_proxy_connect_imans(int fd)
{
    int n;

    n = ioctl(fd, VTPM_PROXY_IOC_CONNECT_TO_IMA_NS, 0);
    if (n < 0) {
        fprintf(stderr,
                "Could not connect vtpm proxy (/dev/tpm%s) to IMA namespace: "
                "ioctl on fd %d failed: %s\n",
                getenv("VTPM_DEVICE_NUM"), fd, strerror(errno));
        return errno;
    }

    return 0;
}

static void usage(FILE *stream, const char *prgname)
{
    fprintf(stream,
            "Tool for testing the setup of IMA namespace with vtpm proxy device\n\n"
            "Usage:\n\n"
            ""
            "%s --create-tpm1.2-device -- <command> [<param1> ... ]\n"
            "%s --create-tpm2-device   -- <command> [<param1> ... ]\n"
            "%s --connect-to-ima-ns <file descriptor>\n"
            "\n"
            "Options:\n"
            "--create-tpm1.2-device:    Opens /dev/vtpmx and creates a TPM 1.2 device.\n"
            "                           Sets environment variables VTPM_DEVICE_NUM,\n"
            "                           VTPM_DEVICE_MAJOR, VTPM_DEVICE_MINOR, VTPM_DEVICE_FD\n"
            "                           with the result from the VTPM_PROXY_IOC_NEW_DEV ioctl\n"
            "                           and keeps the file descriptor to the 'server side'\n"
            "                           open so that 'command' can use it.\n"
            "\n"
            "--create-tpm2-device:      Like above but creates a TPM 2 device.\n"
            "\n"
            "--connect-to-ima-ns <fd> : Uses the 'server side' file descriptor to connect\n"
            "                           a vtpm proxy device with an IMA namespace.\n"
            "\n",
            prgname, prgname, prgname);
}

int main(int argc, char *argv[])
{
    static struct option long_options[] = {
        {"create-tpm1.2-device", no_argument, NULL, 'c'},
        {"create-tpm2-device", no_argument, NULL, '2'},
        {"connect-to-ima-ns", required_argument, NULL, 'C'},
        {"help", no_argument, NULL, 'h'},
        {NULL, 0, NULL, 0},
    };
    unsigned flags = 0;
    char *exec;
    int opt, option_index = 0;
    int ret;
    int fd;

    while ((opt = getopt_long_only(argc, argv, "", long_options,
                                   &option_index)) != -1) {
        switch (opt) {
        case 'c':
            ret = vtpm_proxy_create_dev(false);
            if (ret < 0)
                return EXIT_FAILURE;
            break;
        case '2':
            ret = vtpm_proxy_create_dev(true);
            if (ret < 0)
                return EXIT_FAILURE;
            break;
        case 'C':
            flags |= FLAG_CONNECT_TO_IMA_NS;
            fd = atoi(optarg);
            return vtpm_proxy_connect_imans(fd);
        case 'h':
            usage(stdout, argv[0]);
            return EXIT_SUCCESS;
        default:
            fprintf(stderr, "Unknown option %c\n", opt);
            usage(stderr, argv[0]);
            return EXIT_FAILURE;
        }
    }

    if (optind >= argc) {
        fprintf(stderr, "Missing parameter for program to start.\n\n");
        usage(stderr, argv[0]);
        return EXIT_FAILURE;
    }

    exec = find_file_in_path(argv[optind]);
    if (exec == NULL) {
        fprintf(stderr, "Could not find %s in PATH\n", argv[optind]);
        return EXIT_FAILURE;
    }

    return execve(exec, &argv[optind], __environ);
}
