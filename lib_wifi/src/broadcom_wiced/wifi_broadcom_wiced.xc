// Copyright (c) 2016, XMOS Ltd, All rights reserved
#include <stddef.h>
#include <stdint.h>

#include "wifi_broadcom_wiced.h"
#include "wifi.h"
#include "spi.h"
#include "gpio.h"
#include "xc2compat.h"
#include "xc_broadcom_wiced_includes.h"
#include "lwip/pbuf.h"

#define DEBUG_UNIT WIFI_DEBUG
#include "debug_print.h"
#include "xassert.h"

static const unsigned wifi_bcm_wiced_spi_speed_khz = 100; // TODO: max this out - BCM supports 50MHz
static const spi_mode_t wifi_bcm_wiced_spi_mode = SPI_MODE_1; // XXX: M3 ARM code appears to use SPI_MODE_3, LPC17xx code appears to use SPI_MODE_0...
static const unsigned wifi_bcm_wiced_spi_ss_deassert_ms = 100;
static unsafe client interface spi_master_if i_wifi_bcm_wiced_spi;
static unsigned wifi_bcm_wiced_spi_device_index;

unsafe chanend xcore_wwd_ctrl_external;
unsafe chanend xcore_wwd_pbuf_external;
unsafe client interface fs_basic_if i_fs_global;

unsafe void xcore_wiced_drive_power_line (uint32_t line_state) {
  i_wifi_bcm_wiced_spi.drive_1bit_of_ss_port(0, 2, line_state);
}

unsafe void xcore_wiced_drive_reset_line(uint32_t line_state) {
  i_wifi_bcm_wiced_spi.drive_1bit_of_ss_port(0, 1, line_state);
}

unsafe void xcore_wiced_spi_transfer(wwd_bus_transfer_direction_t direction,
                                     uint8_t * unsafe buffer,
                                     uint16_t buffer_length) {
  i_wifi_bcm_wiced_spi.begin_transaction(wifi_bcm_wiced_spi_device_index,
                                         wifi_bcm_wiced_spi_speed_khz,
                                         wifi_bcm_wiced_spi_mode);
  if (BUS_READ == direction) {
    // Reading from the bus TO buffer, send zeros as data
    for (int i = 0; i < buffer_length; i++) {
      buffer[i] = i_wifi_bcm_wiced_spi.transfer8(buffer[i]);
    }
  } else { // Must be BUS_WRITE
    // Writing to the bus FROM buffer, ignore received data
    for (int i = 0; i < buffer_length; i++) {
      i_wifi_bcm_wiced_spi.transfer8(buffer[i]);
    }
  }
  i_wifi_bcm_wiced_spi.end_transaction(wifi_bcm_wiced_spi_ss_deassert_ms);
}

void xcore_wiced_send_pbuf_to_internal(pbuf_p p) {
  unsafe {
    xcore_wwd_pbuf_external <: p;
  }
}

#define NUM_BUFFERS 10

/*
 * A structure for storing pbuf pointers. It is empty when head == tail.
 */
typedef struct {
  pbuf_p buffers[NUM_BUFFERS];
  unsigned head;
  unsigned tail;
} buffers_t;

// static wiced_time_t scan_start_time;

// /*
//  * Callback function to handle scan results
//  */
// wiced_result_t scan_result_handler(wiced_scan_handler_result_t *malloced_scan_result) {
//   if (malloced_scan_result != NULL) {
//     malloc_transfer_to_curr_thread(malloced_scan_result);

//     if (malloced_scan_result->status == WICED_SCAN_INCOMPLETE) {
//       wiced_scan_result_t *record = &malloced_scan_result->ap_details;

//       WPRINT_APP_INFO( ( "%3d ", record_count ) );
//       print_scan_result(record);
//       ++record_count;
//     } else {
//       wiced_time_t scan_end_time;
//       wiced_time_get_time(&scan_end_time);
//       debug_printf("\nScan complete in %lu milliseconds\n", scan_end_time - scan_start_time);
//     }

//     free(malloced_scan_result);
//   }

//   return WICED_SUCCESS;
// }

static void buffers_init(buffers_t &buffers) {
  buffers.head = 0;
  buffers.tail = 0;
}

static unsafe pbuf_p buffers_take(buffers_t &buffers) {
  xassert(buffers.head != buffers.tail);
  return buffers.buffers[buffers.head];
}

static unsafe pbuf_p buffers_put(buffers_t &buffers, pbuf_p p) {
  buffers.buffers[buffers.tail] = p;
  buffers.tail += 1;
  if (buffers.tail == NUM_BUFFERS) {
    buffers.tail = 0;
  }
  xassert(buffers.head != buffers.tail);
}

static int buffers_is_empty(buffers_t &buffers){
  return (buffers.head == buffers.tail);
}

// Needs to be unsafe due to input of pbuf_p from streaming channel
[[combinable]]
static unsafe void wifi_broadcom_wiced_spi_internal(
    server interface wifi_hal_if i_hal[n_hal], size_t n_hal,
    server interface wifi_network_config_if i_conf[n_conf], size_t n_conf,
    server interface wifi_network_data_if i_data,
    client interface spi_master_if i_spi,
    unsigned spi_device_index,
    streaming chanend c_xcore_wwd_pbuf) {

  // Save the SPI bus details for use from wwd_spi functions
  i_wifi_bcm_wiced_spi = i_spi;
  wifi_bcm_wiced_spi_device_index = spi_device_index;

  buffers_t rx_buffers;
  buffers_init(rx_buffers);

  wiced_ssid_t ssids[] = { {6, "SSID_1"}, {6, "SSID_2"} };
  size_t num_active_networks = 2;

  while (1) {
    select {
      // WiFi HAL interface
      case i_hal[int i].init_radio():
        // Initialise driver and hardware
        debug_printf("Initialising WWD...\n");
        // wwd_result_t result = wwd_management_init(WICED_COUNTRY_UNITED_KINGDOM,
        //                                           NULL);
        // assert(result == WWD_SUCCESS && msg("WWD initialisation failed!"));
        debug_printf("WWD initialisation complete\n");
        break;

      case i_hal[int i].get_hardware_status():
        break;

      case i_hal[int i].get_chipset_power_mode():
        break;

      case i_hal[int i].set_chipset_power_mode():
        break;

      case i_hal[int i].get_radio_tx_power():
        break;

      case i_hal[int i].set_radio_tx_power():
        break;

      case i_hal[int i].get_radio_state():
        break;

      case i_hal[int i].set_radio_state():
        break;

      case i_hal[int i].set_antenna_mode():
        break;

      case i_hal[int i].get_channel():
        break;

      case i_hal[int i].set_channel():
        break;

      // WiFi network configuration interface
      case i_conf[int i].get_mac_address(uint8_t mac_address[6]) -> wifi_res_t result:
        // TODO: implement
        for (int i = 0; i < 6; i++) { // TODO: remove
          mac_address[i] = i;
        }
        result = WIFI_SUCCESS;
        break;

      case i_conf[int i].set_mac_address():
        break;

      case i_conf[int i].get_link_state() -> ethernet_link_state_t state:
        state = ETHERNET_LINK_UP;
        break;

      case i_conf[int i].set_link_state(ethernet_link_state_t state):
        break;

      case i_conf[int i].set_networking_mode():
        break;

      case i_conf[int i].scan_for_networks():
        debug_printf("Internal scan_for_networks\n");
        // wiced_wifi_scan_networks(scan_result_handler, NULL);
        break;

      case i_conf[int i].get_num_networks() -> size_t num_networks:
        debug_printf("Internal get_num_networks\n");
        num_networks = num_active_networks;
        break;

      case i_conf[int i].get_network_ssid(size_t index) -> const wiced_ssid_t * unsafe ssid:
        if (index < num_active_networks) {
          ssid = &ssids[index];
        } else {
          ssid = NULL;
        }
        break;

      case i_conf[int i].join_network(size_t index):
        break;

      case i_conf[int i].leave_network(size_t index):
        break;

      // TODO: WiFi network data interface
      case i_data.receive_packet() -> pbuf_p p:
        debug_printf("Internal receive_packet\n");
        p = buffers_take(rx_buffers);
        if (!buffers_is_empty(rx_buffers)) {
          // If there are still packets to be consumed then notify client again
          i_data.packet_ready();
        }
        break;

      case i_data.send_packet(pbuf_p p):
        // Queue the packet for the WIFI to send it
        debug_printf("Internal send_packet\n");
        // Increment the reference count as LWIP assumes packets have to be
        // deleted, and so does the WIFI library
        pbuf_ref(p);
        wwd_network_send_ethernet_data(p, WWD_AP_INTERFACE);
        break;

      case c_xcore_wwd_pbuf :> pbuf_p p:
        buffers_put(rx_buffers, p);
        i_data.packet_ready();
        break;
    }
  }
}

void wifi_broadcom_wiced_spi(
    server interface wifi_hal_if i_hal[n_hal], size_t n_hal,
    server interface wifi_network_config_if i_conf[n_conf], size_t n_conf,
    server interface wifi_network_data_if i_data,
    client interface spi_master_if i_spi,
    unsigned spi_device_index,
    client interface input_gpio_if i_irq,
    client interface fs_basic_if i_fs) {

  chan c_xcore_wwd_ctrl;
  streaming chan c_xcore_wwd_pbuf;

  par {
    // TODO: 'combine' wifi_broadcom_wiced_spi_internal and xcore_wwd
    // Start the interface task
    {
      unsafe {
        xcore_wwd_ctrl_external = (unsafe chanend)c_xcore_wwd_ctrl;
        i_fs_global = i_fs;
        wifi_broadcom_wiced_spi_internal(i_hal, n_hal, i_conf, n_conf,
                                       i_data, i_spi, spi_device_index,
                                       c_xcore_wwd_pbuf);
      }
    }

    /* The SDK will expect to start this from the call to wwd_management_init
     * by attempting to spawn an RTOS thread. The xCORE implementation of the
     * WWD RTOS callbacks cannot do this, so the driver task is started
     * immediately and waits to be initialised.
     */
    {
      unsafe {
        xcore_wwd_pbuf_external = (unsafe chanend)c_xcore_wwd_pbuf;
      }
      xcore_wwd(i_irq, c_xcore_wwd_ctrl);
    }
  }
}
