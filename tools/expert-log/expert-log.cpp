// expert-log: run a text file through a MoE model and write which experts the router picks
// output: one line per token per layer: "pos layer e0 e1 ... e(n-1)"

#include "arg.h"
#include "common.h"
#include "log.h"
#include "llama.h"

#include <algorithm>
#include <clocale>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static const char * TOPK_NAME = "ffn_moe_topk-";

struct log_state {
    FILE *               out  = nullptr;
    int64_t              pos0 = 0; // position of the first token in the current batch
    std::vector<uint8_t> buf;
};

static bool cb_eval(ggml_tensor * t, bool ask, void * user_data) {
    const bool is_topk = strncmp(t->name, TOPK_NAME, strlen(TOPK_NAME)) == 0;
    if (ask) {
        return is_topk;
    }
    if (!is_topk || t->type != GGML_TYPE_I32) {
        return true;
    }

    auto * st = (log_state *) user_data;
    const int layer = atoi(t->name + strlen(TOPK_NAME));

    const uint8_t * data = (const uint8_t *) t->data;
    if (!ggml_backend_buffer_is_host(t->buffer)) {
        st->buf.resize(ggml_nbytes(t));
        ggml_backend_tensor_get(t, st->buf.data(), 0, st->buf.size());
        data = st->buf.data();
    }

    // t is a view of the argsort result, so rows are not contiguous
    for (int64_t i1 = 0; i1 < t->ne[1]; i1++) {
        fprintf(st->out, "%lld %d", (long long) (st->pos0 + i1), layer);
        for (int64_t i0 = 0; i0 < t->ne[0]; i0++) {
            fprintf(st->out, " %d", *(const int32_t *) (data + i0*t->nb[0] + i1*t->nb[1]));
        }
        fputc('\n', st->out);
    }

    return true;
}

int main(int argc, char ** argv) {
    std::setlocale(LC_NUMERIC, "C");

    common_params params;

    common_init();

    if (!common_params_parse(argc, argv, params, LLAMA_EXAMPLE_COMMON)) {
        return 1;
    }

    const char * out_path = getenv("EXPERT_LOG_OUT");
    if (out_path == nullptr) {
        out_path = "experts.log";
    }

    log_state st;
    st.out = fopen(out_path, "w");
    if (st.out == nullptr) {
        LOG_ERR("%s: cannot open %s\n", __func__, out_path);
        return 1;
    }

    llama_backend_init();
    llama_numa_init(params.numa);

    // one batch = one ubatch, so each callback covers the tokens of exactly one batch
    params.n_batch = params.n_ubatch;

    params.cb_eval = cb_eval;
    params.cb_eval_user_data = &st;
    params.warmup = false;

    auto llama_init = common_init_from_params(params);

    auto * model = llama_init->model();
    auto * ctx   = llama_init->context();

    if (model == nullptr || ctx == nullptr) {
        LOG_ERR("%s: failed to init\n", __func__);
        return 1;
    }

    const llama_vocab * vocab = llama_model_get_vocab(model);
    std::vector<llama_token> tokens = common_tokenize(ctx, params.prompt, llama_vocab_get_add_bos(vocab), true);

    if (tokens.empty()) {
        LOG_ERR("%s: no input tokens (use -f FILE)\n", __func__);
        return 1;
    }
    if (tokens.size() > llama_n_ctx(ctx)) {
        LOG_ERR("%s: %zu tokens do not fit in the context (%u), raise -c\n", __func__, tokens.size(), llama_n_ctx(ctx));
        return 1;
    }

    LOG_INF("%s: %zu tokens, batch %d, writing %s\n", __func__, tokens.size(), params.n_batch, out_path);

    for (size_t i = 0; i < tokens.size(); i += params.n_batch) {
        const int32_t n = (int32_t) std::min<size_t>(params.n_batch, tokens.size() - i);

        st.pos0 = (int64_t) i;
        common_batch batch = common_batch_get_one(ctx, tokens.data() + i, n);
        if (llama_process(ctx, LLAMA_PROCESS_TYPE_DECODE, batch.get())) {
            LOG_ERR("%s: failed to eval at token %zu\n", __func__, i);
            return 1;
        }

        LOG_INF("%s: %zu / %zu\n", __func__, i + n, tokens.size());
    }

    fclose(st.out);

    LOG("\n");
    llama_perf_context_print(ctx);

    llama_backend_free();

    return 0;
}
