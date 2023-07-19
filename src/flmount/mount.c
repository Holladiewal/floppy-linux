#include <sys/mount.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <stdio.h>
#include <sys/mount.h>

//#define DEBUG
#ifndef DEBUG
int puts(const char * __s){return 0;}
#endif

int main(int argc, char* argv[]){
	puts("Insert system disk 2 into the B: drive. Press ENTER to continue.");
	getchar();
	mount("none", "/dev", "devtmpfs", 0, 0);
	mount("/dev/fd1", "/mnt/floppy", "squashfs", MS_RDONLY, 0);
	puts("Mounted floppy!");
	if(!fork()){
		// We are the child!
		puts("Copying coreutils from floppy");
		execl("/mnt/floppy/bin/busybox", "/mnt/floppy/bin/busybox", "cp", "-r", "/mnt/floppy/bin", "/mnt/floppy/sbin", "/mnt/floppy/usr", "/mnt/floppy/etc", "/", 0);
		puts("Copied coreutils from floppy");
	} else {
		// We are either the parent, or we totally failed. But we assume we are awesome!
		argv[0] = "/sbin/init";
		wait(0); // Just wait for the child to terminate
		puts("Handing off to /sbin/init");
		execv("/sbin/init", argv); // And handoff to init
	}
}
