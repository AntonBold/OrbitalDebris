#include "hdmi_rx.h"
#include "xparameters.h"

volatile uint32_t hdmi_rx_connected        = 0;
volatile uint32_t hdmi_rx_stream_up        = 0;
volatile uint32_t hdmi_rx_stream_ups       = 0;
volatile uint32_t hdmi_rx_bridge_overflows = 0;
volatile uint32_t hdmi_rx_vphy_errors      = 0;

#ifndef XPAR_XV_HDMIRXSS_0_BASEADDR

// pattern_gen build: no HDMI hardware
int hdmi_rx_present(void) { return 0; }
int hdmi_rx_init(XScuGic *gic) { (void)gic; return 0; }

#else

#include "xstatus.h"
#include "xil_printf.h"
#include "sleep.h"
#include "xiic.h"
// The Si5342 (behind the mux) only clocks the TX side; RX locks without it
// (Anthony's bring-up app). Off by default: the mux didn't ACK in the first
// integrated build, and RX doesn't need it.
#ifndef HDMI_RX_SETUP_SI5342
#define HDMI_RX_SETUP_SI5342 0
#endif

#if HDMI_RX_SETUP_SI5342
#include "xgpiops.h"
#include "si5432_axi.h"
#endif
#include "xv_hdmirxss.h"
#include "xvphy.h"
#include "xvidc.h"
#include "hdmi_edid_1080p30.h"

// Board I2C (axi_iic_0 -> mux_scl/sda_io): TCA9548-style mux at 0x70; the
// demo selects channel mask 0x04 to reach the Si5342 (0x68).
#define I2C_MUX_ADDR        0x70
#define I2C_MUX_SI5342      0x04

// gpio_emio[0] -> fpga_mux_rst (src/xdc/Genesys_ZU_revC.xdc), active low.
// EMIO GPIO pins start at 78 on Zynq UltraScale+.
#define MUX_RST_EMIO_PIN    78

static XV_HdmiRxSs rxss;
static XVphy       vphy;
#if HDMI_RX_SETUP_SI5342
static XGpioPs     gpio;
#endif

// ---- RX subsystem callbacks (interrupt context) ------------------------------

static void rx_connect_cb(void *ref)
{
    XV_HdmiRxSs *rx = (XV_HdmiRxSs *)ref;
    if (rx->IsStreamConnected == FALSE) {
        vphy.HdmiRxTmdsClockRatio = 0;
        XVphy_IBufDsEnable(&vphy, 0, XVPHY_DIR_RX, FALSE);
        hdmi_rx_connected = 0;
        xil_printf("hdmi_rx: cable disconnected\r\n");
    } else {
        XVphy_IBufDsEnable(&vphy, 0, XVPHY_DIR_RX, TRUE);
        hdmi_rx_connected = 1;
        xil_printf("hdmi_rx: cable connected\r\n");
    }
}

// Stream detected: set up the RX MMCM for its pixel clock
static void rx_stream_init_cb(void *ref)
{
    XV_HdmiRxSs *rx = (XV_HdmiRxSs *)ref;
    XVidC_VideoStream *s = XV_HdmiRxSs_GetVideoStream(rx);
    XVidC_ColorDepth bpc = (s->ColorFormatId == XVIDC_CSF_YCRCB_422) ? XVIDC_BPC_8 : s->ColorDepth;

    if (XVphy_HdmiCfgCalcMmcmParam(&vphy, 0, XVPHY_CHANNEL_ID_CH1, XVPHY_DIR_RX,
                                   s->PixPerClk, bpc) == XST_FAILURE) {
        xil_printf("hdmi_rx: MMCM parameters failed\r\n");
        return;
    }
    XVphy_MmcmStart(&vphy, 0, XVPHY_DIR_RX);
    usleep(10000);
}

// Locked: print the detected timing (docs/PLAN.md SRC-3: expect 1920x1080
// active, 2200x1125 total, progressive, ~30 Hz, RGB)
static void rx_stream_up_cb(void *ref)
{
    XV_HdmiRxSs *rx = (XV_HdmiRxSs *)ref;
    hdmi_rx_stream_up = 1;
    hdmi_rx_stream_ups++;
    xil_printf("hdmi_rx: stream up\r\n");
    XVidC_ReportStreamInfo(&rx->HdmiRxPtr->Stream.Video);
    XVidC_ReportTiming(&rx->HdmiRxPtr->Stream.Video.Timing,
                       rx->HdmiRxPtr->Stream.Video.IsInterlaced);
}

static void rx_stream_down_cb(void *ref)
{
    (void)ref;
    hdmi_rx_stream_up = 0;
    xil_printf("hdmi_rx: stream down\r\n");
}

static void rx_bridge_overflow_cb(void *ref)
{
    (void)ref;
    hdmi_rx_bridge_overflows++;
}

// ---- video PHY callbacks (interrupt context) ---------------------------------

static void vphy_rx_init_cb(void *ref)
{
    XVphy *p = (XVphy *)ref;
    XV_HdmiRxSs_RefClockChangeInit(&rxss);
    p->HdmiRxTmdsClockRatio = rxss.TMDSClockRatio;
}

static void vphy_rx_ready_cb(void *ref)
{
    XVphy *p = (XVphy *)ref;
    XVphy_ChannelId ch = (XVphy_GetPllType(p, 0, XVPHY_DIR_RX, XVPHY_CHANNEL_ID_CH1)
                          == XVPHY_PLL_TYPE_CPLL) ? XVPHY_CHANNEL_ID_CH1 : XVPHY_CHANNEL_ID_CMN0;
    XV_HdmiRxSs_SetStream(&rxss, p->HdmiRxRefClkHz,
                          (u32)(XVphy_GetLineRateHz(p, 0, ch) / 1000000));
}

static void vphy_error_cb(void *ref)
{
    (void)ref;
    hdmi_rx_vphy_errors++;
}

// ---- board clocking ------------------------------------------------------------

#if HDMI_RX_SETUP_SI5342
// Release the I2C mux reset, select the Si5342, and load the demo's
// jitter-attenuator configuration into it
static int board_clock_init(void)
{
    XGpioPs_Config *gcfg = XGpioPs_LookupConfig(XPAR_XGPIOPS_0_BASEADDR);
    if (gcfg == NULL || XGpioPs_CfgInitialize(&gpio, gcfg, gcfg->BaseAddr) != XST_SUCCESS)
        return XST_FAILURE;
    XGpioPs_SetDirectionPin(&gpio, MUX_RST_EMIO_PIN, 1);
    XGpioPs_SetOutputEnablePin(&gpio, MUX_RST_EMIO_PIN, 1);
    XGpioPs_WritePin(&gpio, MUX_RST_EMIO_PIN, 1);
    usleep(1000);

    u8 sel = I2C_MUX_SI5342;
    if (XIic_Send(XPAR_XIIC_0_BASEADDR, I2C_MUX_ADDR, &sel, 1, XIIC_STOP) != 1) {
        xil_printf("hdmi_rx: I2C mux at 0x%02x did not ACK\r\n", I2C_MUX_ADDR);
        return XST_FAILURE;
    }
    if (Si5342_SetI2cDriveLevel() != XST_SUCCESS) {
        xil_printf("hdmi_rx: Si5342 at 0x%02x did not respond\r\n", I2C_SI5342_ADDR);
        return XST_FAILURE;
    }
    hdmi_config_interface_get_SI5432_write_config_registers(
        I2C_SI5342_ADDR, si5342_revd_registers_jitteratt, SI5342_REVD_REG_CONFIG_NUM_REGS);
    return XST_SUCCESS;
}
#endif

// ---- public ----------------------------------------------------------------------

int hdmi_rx_present(void) { return 1; }

int hdmi_rx_init(XScuGic *gic)
{
    int status;

#if HDMI_RX_SETUP_SI5342
    xil_printf("hdmi_rx: configuring Si5342...\r\n");
    if (board_clock_init() != XST_SUCCESS)
        xil_printf("hdmi_rx: Si5342 setup failed, continuing (RX doesn't need it)\r\n");
#endif

    // RX subsystem (before the video PHY: the PHY's RX init calls back into it)
    XV_HdmiRxSs_SetEdidParam(&rxss, (u8 *)hdmi_edid_1080p30, sizeof(hdmi_edid_1080p30));
    XV_HdmiRxSs_Config *rcfg = XV_HdmiRxSs_LookupConfig(XPAR_XV_HDMIRXSS_0_BASEADDR);
    if (rcfg == NULL)
        return XST_DEVICE_NOT_FOUND;
    status = XV_HdmiRxSs_CfgInitialize(&rxss, rcfg, rcfg->BaseAddress);
    if (status != XST_SUCCESS) {
        xil_printf("hdmi_rx: RX subsystem init failed (%d)\r\n", status);
        return status;
    }
    status = XScuGic_Connect(gic, XPAR_FABRIC_XV_HDMIRXSS_0_INTR,
                             (Xil_InterruptHandler)XV_HdmiRxSS_HdmiRxIntrHandler, &rxss);
    if (status != XST_SUCCESS)
        return status;
    XScuGic_Enable(gic, XPAR_FABRIC_XV_HDMIRXSS_0_INTR);

    XV_HdmiRxSs_SetCallback(&rxss, XV_HDMIRXSS_HANDLER_CONNECT,      (void *)rx_connect_cb,         &rxss);
    XV_HdmiRxSs_SetCallback(&rxss, XV_HDMIRXSS_HANDLER_BRDGOVERFLOW, (void *)rx_bridge_overflow_cb, &rxss);
    XV_HdmiRxSs_SetCallback(&rxss, XV_HDMIRXSS_HANDLER_STREAM_DOWN,  (void *)rx_stream_down_cb,     &rxss);
    XV_HdmiRxSs_SetCallback(&rxss, XV_HDMIRXSS_HANDLER_STREAM_INIT,  (void *)rx_stream_init_cb,     &rxss);
    XV_HdmiRxSs_SetCallback(&rxss, XV_HDMIRXSS_HANDLER_STREAM_UP,    (void *)rx_stream_up_cb,       &rxss);

    // Video PHY
    XVphy_Config *vcfg = XVphy_LookupConfig(XPAR_XVPHY_0_BASEADDR);
    if (vcfg == NULL)
        return XST_DEVICE_NOT_FOUND;
    status = XScuGic_Connect(gic, XPAR_FABRIC_XVPHY_0_INTR,
                             (Xil_InterruptHandler)XVphy_InterruptHandler, &vphy);
    if (status != XST_SUCCESS)
        return status;
    status = XVphy_Hdmi_CfgInitialize(&vphy, 0, vcfg);
    if (status != XST_SUCCESS) {
        xil_printf("hdmi_rx: video PHY init failed (%d)\r\n", status);
        return status;
    }
    XScuGic_Enable(gic, XPAR_FABRIC_XVPHY_0_INTR);

    XVphy_SetHdmiCallback(&vphy, XVPHY_HDMI_HANDLER_RXINIT,  (void *)vphy_rx_init_cb,  &vphy);
    XVphy_SetHdmiCallback(&vphy, XVPHY_HDMI_HANDLER_RXREADY, (void *)vphy_rx_ready_cb, &vphy);
    XVphy_SetErrorCallback(&vphy, (void *)vphy_error_cb, &vphy);

    // Drop hot-plug for 500 ms so the source re-reads the EDID (what
    // Anthony's working bring-up app does; demo SetHdmiRxHpd)
    XVphy_MmcmPowerDown(&vphy, 0, XVPHY_DIR_RX, FALSE);
    XVphy_Clkout1OBufTdsEnable(&vphy, XVPHY_DIR_RX, FALSE);
    XVphy_IBufDsEnable(&vphy, 0, XVPHY_DIR_RX, FALSE);
    XV_HdmiRxSs_Stop(&rxss);
    usleep(500000);
    XV_HdmiRxSs_Start(&rxss);
    XVphy_IBufDsEnable(&vphy, 0, XVPHY_DIR_RX, TRUE);

    xil_printf("hdmi_rx: ready, hot-plug toggled, waiting for a source (EDID offers 1080p30 only)\r\n");
    return XST_SUCCESS;
}

#endif // XPAR_XV_HDMIRXSS_0_BASEADDR
