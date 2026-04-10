#include "ggml.h"
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    struct ggml_init_params params = {
        .mem_size = 16 * 1024,
        .mem_buffer = NULL,
        .no_alloc = false,
    };

    struct ggml_context *ctx = ggml_init(params);
    if (!ctx) {
        fprintf(stderr, "ggml_init failed\n");
        return 1;
    }

    struct ggml_tensor *t = ggml_new_tensor_1d(ctx, GGML_TYPE_F32, 4);
    if (!t) {
        fprintf(stderr, "ggml_new_tensor_1d failed\n");
        ggml_free(ctx);
        return 1;
    }

    printf("ggml OK: tensor shape [%lld], type %d\n", (long long)t->ne[0], t->type);

    ggml_free(ctx);
    return 0;
}
