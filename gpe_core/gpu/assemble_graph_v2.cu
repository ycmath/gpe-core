#include <cuda_runtime.h>
#include <stdint.h>           // ← 추가

__device__ __forceinline__
void link_child(uint32_t parent,
                uint32_t child,
                uint32_t* d_head,
                uint32_t* d_next)
{
    uint32_t prev = atomicExch(&d_head[parent], child);
    d_next[child] = prev;
}

// 상단 파라미터 목록에 LUT 인자 추가
extern "C" __global__
void assemble_graph_v2(const uint8_t*  op,
                       const uint32_t* ida,
                       const uint32_t* idb,
                       const uint16_t* cls,
                       const uint32_t* key,
                       const char*     key_blob,   // <── new
                       const uint32_t*  key_off,   // <── new
                       uint8_t*  type,
                       uint32_t* head,
                       uint32_t* next,
                       uint32_t* dkey,
                       int       N)
{
    const int tid  = threadIdx.x + blockIdx.x * blockDim.x;
    const int lane = threadIdx.x & 31;                     // warp lane
    const unsigned mask = 0xFFFFFFFFu;

    if (tid >= n_rows) return;

    const uint8_t code = op[tid];

    if (code == 0u) {                                      // NEW
        uint32_t vid = ida[tid];
        uint16_t cls = meta_cls[tid];
        d_type[vid]  = (cls == 0u ? 0u : (cls == 1u ? 1u : 2u));
        d_head[vid]  = 0xFFFFFFFFu;
        d_next[vid]  = 0xFFFFFFFFu;
    }
    else if (code == 1u) { // APPEND
        uint32_t p = ida[tid], c = idb[tid];
        link_child(p, c, head, next);

        uint32_t kidx = key[tid];
        if (kidx != 0xFFFFFFFFu) {
            // key 문자열의 시작, 끝 offset
            uint32_t s = key_off[kidx];
            uint32_t e = key_off[kidx + 1];
            // 첫 4byte 해시로 dict-slot 미리 계산 (간단 예)
            uint32_t h = *(const uint32_t*)(key_blob + s);
            dkey[c] = h;    // GPU-side 해시 저장
            // 실제 문자열은 host 변환 단계에서 필요 시 slice 사용
        }
    }
}



