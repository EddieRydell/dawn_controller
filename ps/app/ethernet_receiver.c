#include "ethernet_receiver.h"

#include "app_config.h"
#include "e131_receiver.h"
#include "lwip/init.h"
#include "lwip/ip_addr.h"
#include "lwip/opt.h"
#include "lwip/netif.h"
#include "lwip/pbuf.h"
#include "lwip/udp.h"
#include "netif/xadapter.h"
#include "pl_ingest.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xtimer_config.h"

#if defined(XPAR_XEMACPS_0_BASEADDR)
#define DAWN_EMAC_BASEADDR XPAR_XEMACPS_0_BASEADDR
#elif defined(XPAR_PS7_ETHERNET_0_BASEADDR)
#define DAWN_EMAC_BASEADDR XPAR_PS7_ETHERNET_0_BASEADDR
#else
#error "Missing PS ENET0 base address in xparameters.h"
#endif

#define DAWN_GT_COUNTER_LOWER_OFFSET 0x00u
#define DAWN_GT_COUNTER_UPPER_OFFSET 0x04u
#define DAWN_GT_CONTROL_OFFSET 0x08u
#define DAWN_GT_CONTROL_ENABLE 0x01u

static struct netif g_netif;
static struct udp_pcb *g_udp;
static ethernet_receiver_counters_t g_counters;

static ip_addr_t make_ip(const uint8_t octets[4])
{
    ip_addr_t ip;
    IP4_ADDR(&ip, octets[0], octets[1], octets[2], octets[3]);
    return ip;
}

static uint32_t monotonic_ms(void)
{
    uint32_t high;
    uint32_t low;
    uint32_t control;
    uint64_t ticks;

    control = Xil_In32(XPAR_GLOBAL_TIMER_BASEADDR + DAWN_GT_CONTROL_OFFSET);
    if ((control & DAWN_GT_CONTROL_ENABLE) == 0u) {
        Xil_Out32(XPAR_GLOBAL_TIMER_BASEADDR + DAWN_GT_CONTROL_OFFSET, control | DAWN_GT_CONTROL_ENABLE);
    }

    do {
        high = Xil_In32(XPAR_GLOBAL_TIMER_BASEADDR + DAWN_GT_COUNTER_UPPER_OFFSET);
        low = Xil_In32(XPAR_GLOBAL_TIMER_BASEADDR + DAWN_GT_COUNTER_LOWER_OFFSET);
    } while (Xil_In32(XPAR_GLOBAL_TIMER_BASEADDR + DAWN_GT_COUNTER_UPPER_OFFSET) != high);

    ticks = ((uint64_t)high << 32) | low;
    return (uint32_t)((ticks * 1000u) / COUNTS_PER_SECOND);
}

static void copy_receiver_status(void)
{
    const e131_receiver_status_t *status = e131_receiver_status();

    g_counters.e131_valid = status->e131_valid;
    g_counters.e131_rejected = status->e131_rejected;
    g_counters.universes_seen = status->universes_seen;
    g_counters.frames_committed = status->frames_committed;
    g_counters.frames_dropped = status->frames_dropped;
    g_counters.complete_frames = status->complete_frames;
    g_counters.incomplete_sweeps = status->incomplete_sweeps;
    g_counters.ignored_sources = status->ignored_sources;
    g_counters.sequence_anomalies = status->sequence_anomalies;
    g_counters.preview_rejects = status->preview_rejects;
    g_counters.sync_waits = status->sync_waits;
    g_counters.sync_timeouts = status->sync_timeouts;
    g_counters.blackouts = status->blackouts;
    g_counters.last_packet_gap_ms = status->last_packet_gap_ms;
    g_counters.max_packet_gap_ms = status->max_packet_gap_ms;
    g_counters.last_frame_commit_gap_ms = status->last_frame_commit_gap_ms;
    g_counters.max_frame_commit_gap_ms = status->max_frame_commit_gap_ms;
    g_counters.last_universe = status->last_universe;
    g_counters.last_sequence = status->last_sequence;
    g_counters.last_error = status->last_error;
}

static void receive_udp(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port)
{
    uint8_t packet_data[638u];
    uint8_t source_ip[4] = {0u, 0u, 0u, 0u};

    (void)arg;
    (void)pcb;
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
    if (addr != NULL) {
#if LWIP_IPV6
        if (IP_IS_V4(addr)) {
            const ip4_addr_t *ip4 = ip_2_ip4(addr);
            source_ip[0] = ip4_addr1(ip4);
            source_ip[1] = ip4_addr2(ip4);
            source_ip[2] = ip4_addr3(ip4);
            source_ip[3] = ip4_addr4(ip4);
        }
#else
        source_ip[0] = ip4_addr1(addr);
        source_ip[1] = ip4_addr2(addr);
        source_ip[2] = ip4_addr3(addr);
        source_ip[3] = ip4_addr4(addr);
#endif
    }
    e131_receiver_handle_packet(packet_data, p->tot_len, source_ip, monotonic_ms());
    copy_receiver_status();

    pbuf_free(p);
}

int ethernet_receiver_init(void)
{
    ip_addr_t ip = make_ip(g_app_config.ip);
    ip_addr_t netmask = make_ip(g_app_config.netmask);
    ip_addr_t gateway = make_ip(g_app_config.gateway);

    g_counters.last_error = "init";
    e131_receiver_init();
    lwip_init();

    if (xemac_add(&g_netif, &ip, &netmask, &gateway, (unsigned char *)g_app_config.mac, DAWN_EMAC_BASEADDR) == 0) {
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
               (unsigned int)DAWN_EMAC_BASEADDR,
               (unsigned int)g_counters.link_up);
    return 0;
}

void ethernet_receiver_poll(void)
{
    g_counters.link_up = netif_is_link_up(&g_netif) ? 1u : 0u;
    xemacif_input(&g_netif);
    e131_receiver_poll(monotonic_ms());
    copy_receiver_status();
}

uint32_t ethernet_receiver_now_ms(void)
{
    return monotonic_ms();
}

const ethernet_receiver_counters_t *ethernet_receiver_counters(void)
{
    return &g_counters;
}

void ethernet_receiver_print_status(void)
{
    pl_ingest_snapshot_t snapshot;

    pl_ingest_snapshot(&snapshot);
    const e131_receiver_status_t *rx = e131_receiver_status();

    xil_printf("e131_status link=%u ip=%u.%u.%u.%u port=%u rx_packets=%u rx_bytes=%u e131_valid=%u e131_rejected=%u universes_seen=%u frames_committed=%u frames_dropped=%u complete_frames=%u incomplete_sweeps=%u ignored_sources=%u sequence_anomalies=%u preview_rejects=%u sync_mode=%u sync_address=%u sync_waits=%u sync_timeouts=%u blackouts=%u packet_gap_ms=%u max_packet_gap_ms=%u commit_gap_ms=%u max_commit_gap_ms=%u source_locked=%u active_priority=%u source_ip=%u.%u.%u.%u last_universe=%u last_sequence=%u last_error=%s pl_dropped=%u pl_rejected=%u consumer_frames=%u\r\n",
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
               (unsigned int)g_counters.complete_frames,
               (unsigned int)g_counters.incomplete_sweeps,
               (unsigned int)g_counters.ignored_sources,
               (unsigned int)g_counters.sequence_anomalies,
               (unsigned int)g_counters.preview_rejects,
               (unsigned int)rx->sync_mode,
               (unsigned int)rx->sync_address,
               (unsigned int)g_counters.sync_waits,
               (unsigned int)g_counters.sync_timeouts,
               (unsigned int)g_counters.blackouts,
               (unsigned int)g_counters.last_packet_gap_ms,
               (unsigned int)g_counters.max_packet_gap_ms,
               (unsigned int)g_counters.last_frame_commit_gap_ms,
               (unsigned int)g_counters.max_frame_commit_gap_ms,
               (unsigned int)rx->source_locked,
               (unsigned int)rx->active_priority,
               rx->source_ip[0], rx->source_ip[1], rx->source_ip[2], rx->source_ip[3],
               (unsigned int)g_counters.last_universe,
               (unsigned int)g_counters.last_sequence,
               g_counters.last_error,
               (unsigned int)snapshot.frame_dropped,
               (unsigned int)snapshot.frame_rejected,
               (unsigned int)snapshot.consumer_frame_count);
}
