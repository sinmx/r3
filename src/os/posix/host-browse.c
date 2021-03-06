//
//  File: %host-browse.c
//  Summary: "Browser Launch Host"
//  Project: "Rebol 3 Interpreter and Run-time (Ren-C branch)"
//  Homepage: https://github.com/metaeducation/ren-c/
//
//=////////////////////////////////////////////////////////////////////////=//
//
// Copyright 2012 REBOL Technologies
// Copyright 2012-2017 Rebol Open Source Contributors
// REBOL is a trademark of REBOL Technologies
//
// See README.md and CREDITS.md for more information.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//=////////////////////////////////////////////////////////////////////////=//
//
// This provides the ability to launch a web browser or file
// browser on the host.
//

#ifndef __cplusplus
    // See feature_test_macros(7)
    // This definition is redundant under C++
    #define _GNU_SOURCE
#endif

#include <stdlib.h>
#include <stdio.h>
#include <poll.h>
#include <fcntl.h>              /* Obtain O_* constant definitions */
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <time.h>
#include <string.h>
#include <errno.h>
#include <assert.h>

#include "reb-host.h"


#ifndef PATH_MAX
#define PATH_MAX 4096  // generally lacking in Posix
#endif

void OS_Destroy_Graphics(void);


//
//  OS_Get_Current_Dir: C
//
// Return the current directory path as a string and
// its length in chars (not bytes).
//
// The result should be freed after copy/conversion.
//
int OS_Get_Current_Dir(REBCHR **path)
{
    *path = OS_ALLOC_N(char, PATH_MAX);
    if (!getcwd(*path, PATH_MAX-1)) *path[0] = 0;
    return strlen(*path);
}


//
//  OS_Set_Current_Dir: C
//
// Set the current directory to local path. Return FALSE
// on failure.
//
REBOOL OS_Set_Current_Dir(REBCHR *path)
{
    return LOGICAL(chdir(path) == 0);
}


//
//  OS_Request_File: C
//
REBOOL OS_Request_File(REBRFR *fr)
{
    UNUSED(fr);
    return FALSE;
}


//
//  OS_Request_Dir: C
//
// WARNING: TEMPORARY implementation! Used only by host-core.c
// Will be most probably changed in future.
//
REBOOL OS_Request_Dir(REBCHR* title, REBCHR** folder, REBCHR* path)
{
    UNUSED(title);
    UNUSED(folder);
    UNUSED(path);

    return FALSE;
}
