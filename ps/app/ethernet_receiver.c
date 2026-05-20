#include "ethernet_receiver.h"

#include "app_config.h"
#include "e131_parser.h"
#include "frame_pipeline.h"
#include "lwip/init.h"
#include "lwip/ip_addr.h"
#include "lwip/netif.h"
#include "lwip/pbuf.h"
#include "lwip/udp.h"
#include "netif/xadapter.h"
#include "pl_ingest.h"
#include "xil_printf.h"
#include "xparameters.h"

#if defined(XPAR_XEMACPS_0_BASEADDR)
#define DONDER_EMAC_BASEADDR XPAR_XEMACPS_0_BASEADDR
#elif defined(XPAR_PS7_ETHERNET_0_BASEADDR)
#define DONDER_EMAC_BASEADDR XPAR_PS7_ETHERNET_0_BASEADDR
#else
#error "Missing PS ENET0 base address in xparameters.h"
#endif

static struct netif g_netif;
static struct udp_pcb *g_udp;
static ethernet_receiver_counters_t g_counters;
static uint32_t g_universe_bitmap[(DONDER_WORDS_PER_FRAME * 3u + DONDER_SLOTS_PER_UNIVERSE - 1u)
                                  / DONDER_SLOTS_PER_UNIVERSE / 32u + 1u];

static ip_addr_t make_ip(const uint8_t octets[4])
{
    ip_addr_t ip;
    IP4_ADDR(&ip, octets[0], octets[1], octets[2], octets[3]);
    return ip;
}

static void mark_universe_seen(uint16_t universe)
{
    uint32_t offset = (uint32_t)(universe - g_app_config.first_universe);
    uint32_t index = offset / 32u;
    uint32_t mask = 1u << (offset % 32u);

    if (index < (sizeof(g_universe_bitmap) / sizeof(g_universe_bitmap[0]))
        && (g_universe_bitmap[index] & mask) == 0u) {
        g_universe_bitmap[index] |= mask;
        g_counters.universes_seen++;
    }
}

static void receive_udp(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port)
{
    e131_data_packet_t packet;
    e131_parse_result_t parse_result;
    int commit_result;
    uint8_t packet_data[638u];

    (void)arg;
    (void)pcb;
    (void)addr;
    (void)port;

    if (p == NULL) {
        return;
    }

    g_counters.rx_packets++;
    g_counters.rx_bytes += p->tot_len;

    if (p->tot_len > sizeof(packet_data)) {
        g_counters.e131_rejected++;
        g_counters.last_error = "too_large";
        pbuf_free(p);
        return;
    }

    pbuf_copy_partial(p, packet_data, p->tot_len, 0u);
    parse_result = e131_parse_data_packet(packet_data,
                                          p->tot_len,
                                          g_app_config.first_universe,
                                          g_app_config.output_count * g_app_config.pixels_per_output,
                                          &packet);
    if (parse_result != E131_PARSE_OK) {
        g_counters.e131_rejected++;
        g_counters.last_error = e131_parse_result_name(parse_result);
        pbuf_free(p);
        return;
    }

    if (frame_pipeline_write_linear_rgb(packet.first_linear_pixel, packet.rgb_slots, packet.rgb_pixel_count) != 0) {
        g_counters.e131_rejected++;
        g_counters.last_error = "frame_map";
        pbuf_free(p);
        return;
    }

    commit_result = frame_pipeline_commit();
    if (commit_result == 0) {
        g_counters.frames_committed++;
        g_counters.e131_valid++;
        g_counters.last_universe = packet.universe;
        g_counters.last_sequence = packet.sequence;
        g_counters.last_error = "ok";
        mark_universe_seen(packet.universe);
    } else if (commit_result > 0) {
        g_counters.frames_dropped++;
        g_counters.last_error = "pl_busy";
    } else {
        g_counters.e131_rejected++;
        g_counters.last_error = "commit_failed";
    }

    pbuf_free(p);
}

int ethernet_receiver_init(void)
{
    ip_addr_t ip = make_ip(g_app_config.ip);
    ip_addr_t netmask = make_ip(g_app_config.netmask);
    ip_addr_t gateway = make_ip(g_app_config.gateway);

    g_counters.last_error = "init";
    lwip_init();

    if (xemac_add(&g_netif, &ip, &netmask, &gateway, (unsigned char *)g_app_config.mac, DONDER_EMAC_BASEADDR) == 0) {
        g_counters.last_error = "xemac_add";
        return -1;
    }

    netif_set_default(&g_netif);
    netif_set_up(&g_netif);
    g_counters.link_up = netif_is_link_up(&g_netif) ? 1u : 0u;

    g_udp = udp_new();
    if (g_udp == NULL) {
        g_counters.last_error = "udp_new";
        return -1;
    }
    if (udp_bind(g_udp, IP_ADDR_ANY, g_app_config.e131_port) != ERR_OK) {
        udp_remove(g_udp);
        g_udp = NULL;
        g_counters.last_error = "udp_bind";
        return -1;
    }
    udp_recv(g_udp, receive_udp, NULL);
    g_counters.last_error = "ok";

    xil_printf("net status=ready mac=%02x:%02x:%02x:%02x:%02x:%02x ip=%u.%u.%u.%u netmask=%u.%u.%u.%u gateway=%u.%u.%u.%u udp_port=%u emac=0x%08x link=%u\r\n",
               g_app_config.mac[0], g_app_config.mac[1], g_app_config.mac[2],
               g_app_config.mac[3], g_app_config.mac[4], g_app_config.mac[5],
               g_app_config.ip[0], g_app_config.ip[1], g_app_config.ip[2], g_app_config.ip[3],
               g_app_config.netmask[0], g_app_config.netmask[1], g_app_config.netmask[2], g_app_config.netmask[3],
               g_app_config.gateway[0], g_app_config.gateway[1], g_app_config.gateway[2], g_app_config.gateway[3],
               (unsigned int)g_app_config.e131_port,
               (unsigned int)DONDER_EMAC_BASEADDR,
               (unsigned int)g_counters.link_up);
    return 0;
}

void ethernet_receiver_poll(void)
{
    g_counters.link_up = netif_is_link_up(&g_netif) ? 1u : 0u;
    xemacif_input(&g_netif);
}

const ethernet_receiver_counters_t *ethernet_receiver_counters(void)
{
    return &g_counters;
}

void ethernet_receiver_print_status(void)
{
    pl_ingest_snapshot_t snapshot;

    pl_ingest_snapshot(&snapshot);
    xil_printf("e131_status link=%u ip=%u.%u.%u.%u port=%u rx_packets=%u rx_bytes=%u e131_valid=%u e131_rejected=%u universes_seen=%u frames_committed=%u frames_dropped=%u last_universe=%u last_sequence=%u last_error=%s pl_dropped=%u pl_rejected=%u consumer_frames=%u\r\n",
               (unsigned int)g_counters.link_up,
               g_app_config.ip[0], g_app_config.ip[1], g_app_config.ip[2], g_app_config.ip[3],
               (unsigned int)g_app_config.e131_port,
               (unsigned int)g_counters.rx_packets,
               (unsigned int)g_counters.rx_bytes,
               (unsigned int)g_counters.e131_valid,
               (unsigned int)g_counters.e131_rejected,
               (unsigned int)g_counters.universes_seen,
               (unsigned int)g_counters.frames_committed,
               (unsigned int)g_counters.frames_dropped,
               (unsigned int)g_counters.last_universe,
               (unsigned int)g_counters.last_sequence,
               g_counters.last_error,
               (unsigned int)snapshot.frame_dropped,
               (unsigned int)snapshot.frame_rejected,
               (unsigned int)snapshot.consumer_frame_count);
}
