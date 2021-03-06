// Copyright (c) 2015-2017, XMOS Ltd, All rights reserved
#ifndef __xc_broadcom_wiced_includes_h__
#define __xc_broadcom_wiced_includes_h__

// Work around xC keywords used as variable names in Broadcom WICED SDK C files
#define in _in
#define module _module
#define forward _forward
#define interface _interface
#ifdef __XC__
extern "C" {
#endif
#include "wwd_structures.h"
#include "wwd_management.h"
#include "wwd_bus_interface.h"
#include "wwd_sdpcm.h"
#include "wwd_bus_protocol_interface.h"
#include "wwd_resource_interface.h"
#include "wwd_network_interface.h"
#ifdef __XC__
}
#endif
#undef in
#undef module
#undef forward
#undef interface

#endif // __xc_broadcom_wiced_includes_h__
