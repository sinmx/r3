//
//  File: %t-library.c
//  Summary: "External Library Support"
//  Section: datatypes
//  Project: "Rebol 3 Interpreter and Run-time (Ren-C branch)"
//  Homepage: https://github.com/metaeducation/ren-c/
//
//=////////////////////////////////////////////////////////////////////////=//
//
// Copyright 2014 Atronix Engineering, Inc.
// Copyright 2014-2016 Rebol Open Source Contributors
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

#include "sys-core.h"

// !!! Why is there a "LIB_POOL"?  Does that really need optimization?
//
#include "mem-pools.h" // low-level memory pool access

//
//  CT_Library: C
//
REBINT CT_Library(const RELVAL *a, const RELVAL *b, REBINT mode)
{
    //RL_Print("%s, %d\n", __func__, __LINE__);
    if (mode >= 0) {
        return VAL_LIB_HANDLE(a) == VAL_LIB_HANDLE(b);
    }
    return -1;
}


//
//  MAKE_Library: C
//
void MAKE_Library(REBVAL *out, enum Reb_Kind kind, const REBVAL *arg)
{
    if (!IS_FILE(arg))
        fail (Error_Unexpected_Type(REB_FILE, VAL_TYPE(arg)));

    void *lib = NULL;
    REBCNT error = 0;
    REBSER *path = Value_To_OS_Path(arg, FALSE);
    lib = OS_OPEN_LIBRARY(SER_HEAD(REBCHR, path), &error);
    Free_Series(path);
    if (!lib)
        fail (Error_Bad_Make(REB_LIBRARY, arg));

    VAL_LIB_SPEC(out) = Make_Array(1);
    MANAGE_ARRAY(VAL_LIB_SPEC(out));

    Append_Value(VAL_LIB_SPEC(out), arg);
    VAL_LIB_HANDLE(out) = cast(REBLHL*, Make_Node(LIB_POOL));
    VAL_LIB_FD(out) = lib;
    SET_LIB_FLAG(VAL_LIB_HANDLE(out), LIB_FLAG_USED);
    CLEAR_LIB_FLAG(VAL_LIB_HANDLE(out), LIB_FLAG_CLOSED);
    VAL_RESET_HEADER(out, REB_LIBRARY);
}


//
//  TO_Library: C
//
void TO_Library(REBVAL *out, enum Reb_Kind kind, const REBVAL *arg)
{
    MAKE_Library(out, kind, arg);
}


//
//  REBTYPE: C
//
REBTYPE(Library)
{
    REBVAL *val = D_ARG(1);
    REBVAL *arg = D_ARGC > 1 ? D_ARG(2) : NULL;

    // unary actions
    switch(action) {
        case A_CLOSE:
            OS_CLOSE_LIBRARY(VAL_LIB_FD(val));
            SET_LIB_FLAG(VAL_LIB_HANDLE(val), LIB_FLAG_CLOSED);
            SET_VOID(D_OUT);
            break;
        default:
            fail (Error_Illegal_Action(REB_LIBRARY, action));
    }
    return R_OUT;
}
