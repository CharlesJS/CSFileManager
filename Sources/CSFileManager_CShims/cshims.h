//
//  cshims.h
//  
//
//  Created by Charles Srstka on 3/11/23.
//

#if __linux__
#define _GNU_SOURCE
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <uuid/uuid.h>
#endif
