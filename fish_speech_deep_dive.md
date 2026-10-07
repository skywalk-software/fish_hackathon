# Fish Speech / Fish Audio: deep dive

*Researched 2026-10-06.*

**Sources and how this was checked**
- I read the code of `fishaudio/fish-speech` @ `214da3c` (2026-09-17), including the git history back to v1.0.
- I checked the Hugging Face model cards and configs, the docs.fish.audio OpenAPI/AsyncAPI specs, and Tencent's AuK repo.
- Claims marked **[code]** were verified directly in the source.
- Claims marked **[vendor]** are Fish's own numbers and have not been independently reproduced.
- Nothing here was run on a GPU, and no live API calls were made.

---

## 0. TL;DR

| Question | Short answer |
|---|---|
| **What's in the repo today?** | **Only TTS.** One open model: **S2-Pro** (about 4.5B params, Dual-AR, Qwen3-4B backbone), the 44.1 kHz codec, a local HTTP server, a Gradio UI, a React UI, and LoRA fine-tuning scripts. |
| **ASR models?** | **None open.** The repo used to wrap third-party ASR for annotation and an `/v1/asr` endpoint: Whisper, then Alibaba's **SenseVoiceSmall**. This was removed in June 2025. Fish's *cloud* has ASR (`transcribe-1`, `transcribe-1-pro`): batch only, $0.36/hr, closed. |
| **Full-duplex speech-to-speech?** | **Does not exist** from Fish, open or cloud. **Fish Agent v0.1 3B** (Nov 2024) was a *turn-based* end-to-end S2S model (CC-BY-NC-SA). It was removed from the repo in June 2025. The cloud "Fish Agents" product is a *cascaded* pipeline (Deepgram/ElevenLabs ASR → LLM → Fish TTS) over LiveKit WebRTC, with barge-in. Full-duplex audio-to-audio is only on Fish's roadmap (from an interview). |
| **Voice cloning** | Zero-shot from a 10–30 s reference plus its transcript. There's no per-voice training (cloud `train_mode` is only `fast`, which is effectively instant). Multi-speaker cloning works in one request via `<|speaker:N|>` tags. |
| **Multilingual** | 80+ languages, with no phonemes or language ID needed. **Tier 1:** ja, en, zh. **Tier 2:** ko, es, pt, ar, ru, fr, de. Everything else is "global coverage", where quality varies. |
| **Best model** | **S2.1-Pro (cloud only, closed weights).** It covers 83 languages, Fish calls S2-Pro "previous generation", and S2.1 wins 61% of comparisons vs S2-Pro [vendor]. **`s2.1-pro-free` costs $0 until 2026-11-30**, a good fit for a hackathon. |
| **Biggest limitations** | **Licensing:** the open weights are non-commercial only. **Hardware:** a 16–24 GB GPU is needed locally, and the native path is only about RTF 0.66 even compiled. **Local server:** it's serial, and it only streams if the text has speaker tags. **Quality gap:** local output trails the web demo because Fish's text-normalization frontend is closed. **Published benchmarks:** these used Fish's online engine. **Scope:** it's TTS only. **Cloud ASR:** no streaming. **Independent arenas:** S2-Pro is at #33 on Artificial Analysis, so it's good but not top. |
| **vs "AUK" (Tencent AuK, 2026-09-09)** | **Fish wins on:** 80+ vs 2 languages, true streaming at about 100 ms TTFA vs whole-clip diffusion with a duration you must specify, long-form and multi-turn dialogue, a production serving stack, and a hosted API. **AuK wins on:** speech *editing*, enhancement and separation (Fish does none), and a permissive MIT license on its own weights. See §9. |

---

## 1. Model lineage: what Fish has shipped

| Model | Date | Weights / license | Type | Status |
|---|---|---|---|---|
| Fish Speech 1.0 – 1.4 | 2023–2024 | Open, CC-BY-NC-SA | Dual-AR TTS + VQ-GAN/Firefly vocoder | Legacy |
| Fish Speech 1.5 | Dec 2024 | Open, CC-BY-NC-SA | TTS (+ SenseVoice ASR wrapper in the server) | Legacy (tag `v1.5.1`) |
| **Fish Agent v0.1 3B** | Nov 2024 | Open, CC-BY-NC-SA (`fishaudio/fish-agent-v0.1-3b`) | **End-to-end speech-to-speech, turn-based.** Qwen2.5-3B-Instruct continue-pretrained on 200B voice+text tokens; 8 languages; uses the 1.4 codec | "Early alpha"; code removed from `main` (#986, 2025-06-03); HF Space broken |
| OpenAudio S1 (4B) / **S1-mini** (0.5B) | Jun 2025 | S1 is cloud only; S1-mini is open (CC-BY-NC-SA, `fishaudio/s1-mini`, login gate) | TTS, `(parenthesis)` emotion tags, 13 languages | `s1` still on the API |
| **S2-Pro** | 2026-03-09 | Open, **Fish Audio Research License** (non-commercial; covers the code too since v2.0) | TTS, free-form `[tag]` control, 80+ languages | Current open model |
| **S2.1-Pro** | 2026-06-23 | **Cloud only** | TTS, 83 languages, ~70–90 ms TTFA, 61% win rate vs S2-Pro [vendor] | Recommended API model |
| `drama-3-preview` | 2026-09-23 | Cloud only | TTS with plain-language direction | Preview |
| `transcribe-1` / `transcribe-1-pro` | Spring 2026 / 2026-09-18 | Cloud only | ASR (batch, diarization and emotion tags on Pro) | Beta |

Fish Agent v0.1 [code, `v1.5.1:tools/fish_e2e.py`, `tools/server/agent/*`]:
- Encoded your audio into the same VQ tokens and fed them to a Qwen-based LLM, which emitted interleaved text and VQ tokens.
- The server exposed `/v1/chat` with SSE.
- It was push-to-talk / turn-based: no VAD, no interruption, no simultaneous listen-and-speak.
- So it was *speech-to-speech*, but never *full-duplex*.

---

## 2. S2-Pro architecture, from the actual checkpoint

From `huggingface.co/fishaudio/s2-pro/config.json` and the weight index [code]:

| Component | Details |
|---|---|
| **Slow AR** (`text_model`) | Qwen3-4B shape: 36 layers, d=2560, 32 query heads / 8 KV heads (GQA), head_dim 128, FFN 9728, QK-norm, RoPE base 1e6, **max_seq_len 32,768**. Vocab 155,776 = Qwen3 text vocab + 4,096 `<|semantic:i|>` tokens. The shipped `chat_template.jinja` is Qwen3's (tools, `<think>`), which suggests it was initialised from Qwen3. |
| **Fast AR** (`audio_decoder`) | 4 layers, d=2560 (≈0.4B). At each time step it generates the 9 residual codebooks conditioned on the slow AR hidden state (sequence length 11). |
| **Total weights** | 9.12 GB bf16 ≈ **4.56B params**. |
| **Codec** (`codec.pth`, 446M params, 1.87 GB, loaded in fp32) | Modified DAC at **44.1 kHz**, fully causal, hop 512 × 4 downsample = 2048 samples → **21.5 frames/s (46 ms/frame)**. 10 codebooks: 1 semantic (4096 entries, distilled toward w2v-BERT 2.0 layer-16 features) + 9 RVQ (1024 entries), with transformer pre/post modules and an EVA-GAN-style decoder (paper). |
| **No audio encoder in the weights** | The code has `AudioPart` and `audio_projector` hooks for continuous audio input, but the released checkpoint contains **only** `text_model.*` and `audio_decoder.*`. **The open model cannot listen.** No ASR and no S2S is possible with these weights. |
| **Prompt format** (`generate_long`) | `system: "convert the provided text to speech reference to the following:\n\nText:\n<|speaker:0|>{ref transcript}\n\nSpeech:\n{ref VQ codes}"` → `user: {text}` → `assistant <|voice|>` → generated semantic tokens. |
| **Sampling** | top-p plus **top-k = 30 (hard-coded)**, with constrained decoding: only semantic tokens and `<|im_end|>` are allowed. "Repetition-Aware Sampling" swaps in a temperature-1.0 sample when a token repeats within a 10-frame window. |
| **Training (paper)** | 10M+ hours, ~80 languages. Data pipeline: separation + VAD → a w2v-BERT speech-quality model → a **"rich-transcription" ASR (a Qwen3-Omni-30B-A3B fine-tune that emits `<|speaker:N|>` and `[emotion]` tags; not released)**. Pretraining at 8k then 16k context, then SFT, then a GRPO variant (LoRA r16 on MLPs). Reward = ASR re-transcription accuracy + quality-model score + voiceprint similarity. The paper notes the 8k pretraining context as a long-form limitation. |

---

## 3. Capabilities

### 3.1 Voice cloning

- **Local / open weights:** pass reference `audio` + exact `text` transcript.
  - The codec encodes the audio into VQ tokens, which are placed in the system prompt. This is in-context learning with no training.
  - About 10–30 s is recommended. 30 s ≈ 650 tokens of context.
- **Gotcha [code]:** when several references are passed, reference *i* is automatically tagged `<|speaker:i|>`.
  - Two clips of the *same* person therefore get treated as two different speakers.
  - Fix: prefix each reference text with `<|speaker:0|>` yourself.
  - The bundled web UIs don't do this for you.
- **Saved voices (local):** `references/<id>/*.wav` + matching `*.lab` transcript, then use `reference_id`. The encoding is cached in memory when `use_memory_cache: "on"`.
- **Cloud:**
  - Inline `references` (msgpack only).
  - Or `POST /model` with 1–20 clips (+ optional transcripts; ASR fills them in if omitted). `enhance_audio_quality` defaults to true, and the voice is usable immediately. Then pass `_id` as `reference_id`.
  - Fish's guidance: "2–3 clips of 15–20 s".
- **Fine-tuning (LoRA)** exists, but:
  - (a) the docs and `text2semantic_finetune.yaml` still point at **openaudio-s1-mini**, not S2-Pro;
  - (b) Fish explicitly warns against fine-tuning the RL-aligned S2 model, because it degrades;
  - (c) by default LoRA learns speaking *style*, not timbre.
  - Treat fine-tuning as unsupported for S2.

### 3.2 Multilingual

- 80+ languages (S2.1: 83) with automatic language handling and no G2P.
- Tier 1 is ja/en/zh. Tier 2 is ko/es/pt/ar/ru/fr/de.
- **[vendor]** On the MiniMax 24-language test set, S2 has the best WER in 11/24 languages and the best speaker similarity in 17/24.
- Long-tail languages are trained on far less data. Test your target language before you commit.
- Cross-lingual cloning (an English reference speaking Japanese) works because the reference is just context.
- The local `normalize` flag is a **no-op** [code]. Write numbers out as words yourself when using local inference. The cloud API does normalize en/zh.

### 3.3 Expressive control

- **S2 family:** free-form `[bracket]` text anywhere inline, e.g. `[whisper]`, `[laughing nervously]`, `[professional broadcast tone]`, `[pause]`, `[pitch up]`. The README cites 15,000+ unique tags seen in training.
  - Brackets are ordinary text the model learned, not control tokens.
  - Emotions work best at the start of a sentence; sound effects can go anywhere. Fish recommends at most about 3 combined cues.
- **S1 (legacy):** a fixed set of `(parenthesis)` tags.
- **Cloud extras:**
  - Phoneme overrides with `<|phoneme_start|>…<|phoneme_end|>` (Arpabet / pinyin / romaji).
  - `pronunciation_dictionary`.
  - `prosody.speed` / `volume`.
  - These are **not** in the local server.

### 3.4 Multi-speaker and multi-turn

- Write the text as `<|speaker:0|>Hi there.<|speaker:1|>Hey! [laughing] Long time.` and pass one reference per speaker, in index order.
- The local engine:
  - splits on speaker tags;
  - groups turns into batches of at most 5 speakers and at most `chunk_length` UTF-8 bytes;
  - generates each batch with all previously generated audio kept in context, for consistent prosody across turns.
- The context grows each batch. The run errors out past 32,768 − 2,048 tokens, roughly 20+ minutes of audio.

---

## 4. ASR: what actually exists

| Option | Status |
|---|---|
| **Open ASR from Fish** | **None.** |
| Repo history | `tools/whisper_asr.py` (OpenAI Whisper), then `tools/sensevoice/*` + `/v1/asr` using **`iic/SenseVoiceSmall`** via FunASR, capped at 30 s of audio. Removed in V1.5 (#920) and #1016. These were third-party models used for dataset annotation and reference transcription. |
| Internal (paper) | A "rich-transcription" ASR fine-tuned from **Qwen3-Omni-30B-A3B** for data labelling and RL reward. Proprietary. |
| **Cloud `POST /v1/asr`** (beta) | Model is chosen with the `model` header: `transcribe-1-pro` or `transcribe-1`. **Batch only, with no streaming endpoint.** Pro accepts up to 60 min of audio and adds diarization (`speaker_turns`), word timestamps (`ignore_timestamps=false`) and audio-event tags. **$0.36 per audio hour.** No WER is published. Its output format (`<|speaker:N|>` + inline `[laughter]`) matches the internal ASR, so it is *probably* the productised version (inference, not confirmed). |
| Cloud realtime STT | Only through the OpenAI-Realtime-compat socket, with manual `commit`. No server VAD and no partial results. |
| **For live voice apps** | Use a real streaming ASR: Deepgram Nova-3 (what Fish Agents uses), ElevenLabs Scribe v2 Realtime, Kyutai STT (CC-BY, about 0.5 s delay), or Qwen3-ASR (Apache-2.0, streaming). |

---

## 5. Speech-to-speech and full-duplex: what actually exists

| Option | What it really is |
|---|---|
| **Fish Agents** (cloud, public beta) | **Cascaded:** ASR (`deepgram:nova-3` default ≈0.4 s, or ElevenLabs Scribe v2) → LLM (Gemini Flash-Lite / GPT / Gemma, or your own OpenAI-compatible `/chat/completions`, 10 s cap) → Fish TTS. Runs over **LiveKit WebRTC** with barge-in (`user.interrupt`), agent states, telephony, and a widget. SDKs: `@fishaudio/agent-client`, `agent-react`, `agent-protocol` (0.3.0). **$0.06/min all-in.** Feels duplex, but it isn't one audio-to-audio model. |
| OpenAI-compat Realtime socket | `wss://api.fish.audio/compat/v1/realtime`: TTS plus manual-commit STT. **No LLM in the loop** and no server VAD. |
| Fish Agent v0.1 3B (open, 2024) | Real end-to-end S2S but turn-based. It's stale and its code is gone from `main`. To try it, check out `v1.5.1`. |
| **Full-duplex audio-to-audio** | **Not released.** It's mentioned only as roadmap (Aug 2026 interview). |
| If you *need* full-duplex now | Kyutai **Moshi** (CC-BY, English, fixed voice, about 200 ms), NVIDIA **PersonaPlex-7B** (built on Moshi, voice and persona prompts, commercial OK), **MiniCPM-o 4.5** (Apache, voice clone), or OpenAI **GPT-Live-1** (closed). Fish fits only as the voice layer of a cascaded agent. |

---

## 6. Local setup (open weights)

### 6.1 Requirements

- **24 GB NVIDIA GPU** recommended; Linux or WSL. There's also a ROCm Docker image (RDNA3/4) and an Intel XPU path. Python 3.12, torch 2.8.
- VRAM budget [code]:

  | Item | Size |
  |---|---|
  | Weights (bf16) | 9.1 GB |
  | Codec (fp32) | 1.9 GB |
  | **KV cache pre-allocated for the full 32,768 context** | 36 × 2 × 8 × 128 × 32768 × 2 B ≈ **4.8 GB** |
  | Activations / logits | extra |

  - PR #1312 measured **15.16 GB peak reserved** (GV100). 16 GB cards are borderline. Lowering `max_seq_len` should shrink the cache further (untested hack). You also need ≥32 GB of system RAM for loading.
- **macOS:** `ModelManager` automatically selects **MPS** if it's available. `--compile` isn't supported on macOS/Windows.
  - Measured on an M4 Pro 48 GB: **8.31 frames/s ≈ 0.39× real-time**, so it works but is slower than playback.
  - Community MLX (`mlx-community/fish-audio-s2-pro-bf16`) and GGUF (`rodrigomt/s2-pro-gguf`) ports exist but are unofficial.

### 6.2 Install and download

```bash
git clone https://github.com/fishaudio/fish-speech && cd fish-speech
apt install portaudio19-dev libsox-dev ffmpeg          # Linux
uv sync --python 3.12 --extra cu129                     # or: pip install -e .[cu129]  (cu126/cu128/cpu)
hf download fishaudio/s2-pro --local-dir checkpoints/s2-pro   # ~11 GB, ungated
```

Docker:

```bash
docker compose --profile server up       # API on :8080
COMPILE=1 docker compose --profile webui up
```

Mount `./checkpoints` and `./references`.

### 6.3 CLI (three stages)

```bash
# 1) reference audio -> VQ tokens (writes fake.npy)
python fish_speech/models/dac/inference.py -i ref.wav --checkpoint-path checkpoints/s2-pro/codec.pth
# 2) text -> semantic tokens (writes output/codes_0.npy); --prompt-audio ref.wav also works directly
python fish_speech/models/text2semantic/inference.py \
  --text "<|speaker:0|>[excited] Hello hackathon!" --prompt-text "exact transcript of ref" \
  --prompt-tokens fake.npy --compile        # --half if no bf16
# 3) tokens -> wav
python fish_speech/models/dac/inference.py -i output/codes_0.npy
```

### 6.4 Server and UIs

```bash
python tools/api_server.py --llama-checkpoint-path checkpoints/s2-pro \
  --decoder-checkpoint-path checkpoints/s2-pro/codec.pth --listen 0.0.0.0:8080 --compile [--api-key SECRET]
python tools/run_webui.py --compile                      # Gradio
cd awesome_webui && npm i && npm run build               # React UI, then visit http://host:8080/ui
```

### 6.5 Faster serving

- `--compile` gives about a 10× speedup per the Docker docs [vendor].
- For production throughput (continuous batching, paged KV, CUDA graphs, prefix cache), use **SGLang-Omni** (`sglang_omni/models/fishaudio_s2_pro`) or **vLLM-Omni** (`recipes/fishaudio/Fish-Speech-S2-Pro.md`).
- Fish's 100 ms TTFA / RTF 0.195 numbers come from SGLang on an H200. The repo's own server will not reach them (see §8).

**Third-party serving engines.** Both expose an OpenAI-style `POST /v1/audio/speech` with PCM streaming. The repo's own server does **not** have this endpoint; #1272 was closed as not planned.

| Engine | Launch | Cloning params | Measured (by the engine authors) |
|---|---|---|---|
| **SGLang-Omni** | `sgl-omni serve --model-path fishaudio/s2-pro --config examples/configs/s2pro_tts.yaml` | `references:[{audio_path,text}]` or `ref_audio` / `ref_text`; `top_k` must be ≤30 or it crashes | H200 batch 1: RTF 0.34, TTFA ≈140 ms (day-0 README). H20: 151 ms TTFP at c=1, **32.8 audio-s/s at c=64**. Vocoder defaults to CPU; uses about 20 GB more memory than vLLM. No Apple Silicon. |
| **vLLM-Omni** | `vllm serve fishaudio/s2-pro --omni` | `ref_audio` + `ref_text`, `voice:"default"` | H20: **84 ms TTFP at c=1** (≈RTF 0.26). H100 PCIe: 613 ms TTFP / RTF 0.60. About 48 GiB reserved on an A800 (the KV pool takes it). There's a 2-GPU split profile. |
| Community | `rodrigomt/s2-pro-gguf` (s2.cpp, q8 5.3 GB down to q2 2.4 GB, Vulkan/CPU, alpha); `mlx-community/fish-audio-s2-pro-bf16` (MLX on Mac); `audio.cpp` (3× real-time on a 5090); fp8 and w4a16 quants | – | Unofficial. Quality not verified. |

Fish's own S2.1 serving (closed) claims 8,006 tok/s at c=64 on an H200 with FP8. The FP8 kernels are open-sourced as `fishaudio/fish-scales-ops`.

---

## 7. API reference

### 7.1 Local server (`tools/api_server.py`, kui/ASGI) [code]

| Endpoint | Body | Notes |
|---|---|---|
| `GET/POST /v1/health` | – | `{"status":"ok"}` |
| `POST /v1/tts` | JSON **or** msgpack `ServeTTSRequest` | Returns audio bytes. |
| `POST /v1/vqgan/encode` / `decode` | msgpack | Raw codec access. Decode returns float16 PCM. |
| `POST /v1/references/add` | multipart `id`, `audio`, `text` | Saves to `references/<id>/sample.*` + `.lab` |
| `GET /v1/references/list` | – | `?format=json` for JSON; the default is msgpack. |
| `DELETE /v1/references/delete` | `reference_id` | |
| `POST /v1/references/update` | `old_reference_id`, `new_reference_id` | Rename |
| `GET /ui` | – | Built React UI |

Auth uses `Authorization: Bearer <key>`, enforced only when the server starts with `--api-key`. There's **no per-request model selection**: the model is fixed when the server starts.

**`ServeTTSRequest` fields, and which ones actually do something locally:**

| Field | Default | Effective locally? |
|---|---|---|
| `text` | – | yes |
| `references` `[{audio, text}]` | `[]` | yes. `audio` may be **base64 in JSON** (decoded if the string is longer than 255 chars) or raw bytes in msgpack. |
| `reference_id` | null | yes (from the `references/` folder) |
| `format` | `wav` | `wav` / `pcm` / `mp3` / `opus` |
| `streaming` | false | yes, but **WAV only**, and see §8 |
| `chunk_length` | 200 (100–1000) | Only used as the byte budget when grouping **speaker-tagged** turns. |
| `max_new_tokens` | 1024 | yes. **1024 tokens ≈ 47.6 s of audio per batch**, so raise it for long single-turn text. |
| `temperature` / `top_p` | 0.8 / 0.8 | yes |
| `seed` | null | yes |
| `use_memory_cache` | `off` | yes. Set `on` to cache reference encodings. |
| `repetition_penalty` | 1.1 | **no**: accepted, never applied (RAS is used instead) |
| `normalize` | true | **no-op** locally |
| `latency` | `normal` | **no-op** locally (cloud-only) |

Local Python call, JSON + base64 clone + streaming playback:

```python
import base64, requests
ref = base64.b64encode(open("ref.wav", "rb").read()).decode()
body = {
    # Wrap each sentence in <|speaker:0|> so the server chunks and streams it (see §8)
    "text": "<|speaker:0|>[warm] Welcome to the demo.<|speaker:0|>Here is the second sentence.",
    "references": [{"audio": ref, "text": "<|speaker:0|>Exact transcript of ref.wav"}],
    "format": "wav", "streaming": True, "chunk_length": 100,
    "max_new_tokens": 2048, "temperature": 0.7, "top_p": 0.8, "use_memory_cache": "on",
}
with requests.post("http://127.0.0.1:8080/v1/tts", json=body, stream=True,
                   headers={"Authorization": "Bearer SECRET"}) as r:
    r.raise_for_status()
    with open("out.wav", "wb") as f:           # 44-byte WAV header, then int16 PCM @ 44.1 kHz mono
        for chunk in r.iter_content(4096):
            f.write(chunk)
```

Save a voice once, then reuse it by id:

```bash
curl -X POST http://127.0.0.1:8080/v1/references/add \
  -F id=alice -F audio=@alice.wav -F "text=Exact transcript of alice.wav"
python tools/api_client.py --url http://127.0.0.1:8080/v1/tts --text "Hi" --reference_id alice --output demo
```

### 7.2 Fish Audio cloud API (verified against the live OpenAPI/AsyncAPI specs)

| Topic | Details |
|---|---|
| Base URLs | `https://api.fish.audio` and `wss://api.fish.audio`. Auth: `Authorization: Bearer $FISH_API_KEY`. |
| **Model selection** | A **`model` HTTP header**, not a body field. TTS: `s2.1-pro` (default; it's also what you get if the header is missing or wrong, and it's paid), `s2.1-pro-free`, `s2-pro`, `s1`, `drama-3-preview`. ASR: `transcribe-1-pro`, or `transcribe-1` (the default and the fallback for unrecognised values). |
| `POST /v1/tts` | JSON, or **msgpack (required for inline `references`)**. Streams chunked audio. |
| Extra cloud-only fields | `prosody{speed, volume, normalize_loudness}`, `sample_rate` (8k–44.1k; opus is 48k), `mp3_bitrate`, `opus_bitrate`, `latency` (`low` / `normal` / `balanced`), `min_chunk_length`, `condition_on_previous_chunks`, `pronunciation_dictionary`. `reference_id` can be an **array** for multi-speaker (S2 family only). |
| `POST /v1/tts/stream/with-timestamp` | SSE with `audio_base64` plus cumulative word `alignment`. |
| **`wss://…/v1/tts/live`** | Every frame is a msgpack map. Client sends `{"event":"start","request":{…}}`, then `{"event":"text","text":…}` repeatedly, `{"event":"flush"}`, and finally `{"event":"stop"}`. Server sends `{"event":"audio","audio":bytes}` repeatedly and then `{"event":"finish","reason":"stop"|"error"}`. A `/with-timestamp` variant adds alignment. |
| `POST /v1/asr` | multipart: `audio`, `language`, `ignore_timestamps`, plus Pro-only `diarize`, `num_speakers`, `tag_audio_events`. |
| `POST /model` | multipart: `type=tts`, `title`, `train_mode=fast`, `voices[]` (1–20), `texts[]`, `visibility=private`, `enhance_audio_quality=true`. |
| `POST /v1/voice-design` | $0.01/request. |
| **Pricing** | TTS **$15 per million UTF-8 bytes** (≈12 h of speech) for s2.1-pro / s2-pro / s1. **`s2.1-pro-free` costs $0 until 2026-11-30** (fair use, no SLA, requests may be used for training). ASR **$0.36/h**. Agents $0.06/min. |
| **Concurrency** | 5 under $100 prepaid; 15 at $100+; 50 at $1,000+. Shared across all keys, and ASR counts against it. The native API returns 429 with no `Retry-After`. |
| **SDKs** | `pip install fish-audio-sdk` (`import fishaudio`, v1.3.0 defaults to `s2-pro`, so **always pass `model=`**; SDK defaults are `latency="balanced"` and `chunk_length=200`). `npm i fish-audio` (v0.1.0, defaults to `s1`). |
| **Compat layers** | OpenAI (`/compat/v1`, `model="fish-audio/s2.1-pro"`), ElevenLabs, OpenRouter, Groq. |
| **Integrations** | LiveKit `livekit-agents[fishaudio]`, Pipecat `pipecat-ai[fish]` (`FishAudioTTSService`, WebSocket), n8n, Telnyx, MCP server at `https://api.fish.audio/mcp`. |

Cloud examples (untested; set `FISH_API_KEY`):

```python
# (a) TTS with a saved voice: SDK
from fishaudio import FishAudio
from fishaudio.types import ReferenceAudio, TTSConfig
from fishaudio.utils import save
client = FishAudio()
audio = client.tts.convert(text="[excited] Hello from Fish!", reference_id="<voice-id>",
                           model="s2.1-pro-free", config=TTSConfig(format="mp3", latency="balanced"))
save(audio, "out.mp3")

# (b) Instant clone (the SDK sends msgpack for you)
audio = client.tts.convert(text="Same voice, new words.", model="s2.1-pro-free",
        references=[ReferenceAudio(audio=open("ref.wav", "rb").read(), text="Transcript of ref.wav")])
```

```python
# (c) Streaming WebSocket TTS (raw protocol): feed LLM tokens as they arrive
import asyncio, os, msgpack, websockets
async def speak(token_iter):
    hdrs = {"Authorization": f"Bearer {os.environ['FISH_API_KEY']}", "model": "s2.1-pro-free"}
    pack = lambda o: msgpack.packb(o, use_bin_type=True)
    async with websockets.connect("wss://api.fish.audio/v1/tts/live", additional_headers=hdrs, max_size=None) as ws:
        await ws.send(pack({"event": "start", "request": {"text": "", "reference_id": "<voice-id>",
                            "format": "pcm", "sample_rate": 24000, "latency": "balanced"}}))
        async def send():
            for t in token_iter:
                await ws.send(pack({"event": "text", "text": t}))
            await ws.send(pack({"event": "flush"})); await ws.send(pack({"event": "stop"}))
        task = asyncio.create_task(send())
        async for raw in ws:                              # 16-bit mono PCM @ 24 kHz
            m = msgpack.unpackb(raw, raw=False)
            if m.get("event") == "audio": yield m["audio"]
            elif m.get("event") == "finish": break
        await task
```

```python
# (d) ASR with diarization: raw multipart (the SDK drops speaker_turns)
import os, httpx
r = httpx.post("https://api.fish.audio/v1/asr",
    headers={"Authorization": f"Bearer {os.environ['FISH_API_KEY']}", "model": "transcribe-1-pro"},
    files={"audio": ("meeting.mp3", open("meeting.mp3", "rb"))},
    data={"ignore_timestamps": "false", "num_speakers": "2"}, timeout=900)
print(r.json()["text"], r.json().get("speaker_turns"))

# (e) Persistent cloned voice
voice = client.voices.create(title="Alice", voices=[open("a.wav", "rb").read()],
                             texts=["Transcript of a.wav"], visibility="private")
print(voice.id)   # -> use as reference_id
```

```python
# (f) Drop-in OpenAI SDK
from openai import OpenAI
c = OpenAI(base_url="https://api.fish.audio/compat/v1", api_key=os.environ["FISH_API_KEY"])
with c.audio.speech.with_streaming_response.create(model="fish-audio/s2.1-pro-free", input="Hi",
        voice="<voice-id>", response_format="mp3") as r:   # compat default format is pcm
    r.stream_to_file("hi.mp3")
```

---

## 8. Limitations

### 8.1 Licensing and legal
- **Open weights and code are under the Fish Audio Research License** (2026-03-07): research and non-commercial use only.
  - "Commercial Purpose" explicitly includes your own product, a hosted service or API, and **internal business operations**. Commercial use needs a written license (business@fish.audio).
  - It requires a "Built with Fish Audio" notice.
  - It forbids using outputs to train or improve other foundation models.
  - Older models (1.x, S1-mini, Agent) are CC-BY-NC-SA.
- **Cloud:** paid usage grants commercial rights under the ToS. `s2.1-pro-free` is ambiguous ("some commercial scenarios may have restrictions"; companies over $1M ARR should contact Fish).
- The free web plan is non-commercial. By default, usage data may be used for training; zero data retention is Enterprise-only.
- No documented output watermark (unlike Chatterbox, which uses Perth). Voice-cloning consent is on you.

### 8.2 Scope
- **TTS only.** No ASR, no speech-to-speech, no full-duplex, no voice conversion via the API (Voice Changer is web-only), and no speech editing or enhancement.
- The open S2-Pro is now "previous generation". The better S2.1-Pro is closed.

### 8.3 Local inference engine [code]
1. **One request at a time per process.**
   - A single worker thread with a fixed batch size of 1. The async endpoint runs the generator synchronously, so concurrent requests queue.
   - `--workers N` loads N full copies of the model (about 16 GB+ each).
   - For concurrency, use SGLang-Omni or vLLM-Omni.
2. **Streaming is per text batch, not per token.**
   - Text is split only on `<|speaker:N|>` tags. Plain text is generated as one batch, so `streaming:true` emits the WAV header and then **all the audio at the end**.
   - Workaround: prefix every sentence with `<|speaker:0|>` and set `chunk_length≈100`. Time to first audio is then roughly one sentence's generation time.
   - Streaming is WAV only.
3. **`max_new_tokens=1024` ≈ 47.6 s of audio per batch.** Longer single-turn text gets truncated unless you raise it or split it into tagged turns.
4. **No-op parameters:** `normalize`, `latency`, `repetition_penalty` and `iterative_prompt`. `top_k` is fixed at 30 and isn't exposed.
5. **VRAM:** 24 GB recommended. About 4.8 GB of that is a KV cache pre-allocated for the full 32k context. No official quantised S2 build (`tools/llama/quantize.py` exists but targets the older format).
6. **Platforms:** Linux/WSL first. `--compile` doesn't work on macOS or Windows. MPS is automatically selected on Macs but is unbenchmarked.
7. **Stale docs:** the fine-tuning docs, `API_FLAGS.txt` and `text2semantic_finetune.yaml` still reference `openaudio-s1-mini`. The OpenAPI title says "1.5.0".
8. **Reference handling:** multiple references are treated as multiple speakers unless you tag them yourself (§3.1).
9. **Long-form:** every batch adds its audio to the context, so later batches slow down. There's a hard error past about 30.7k prompt tokens.

### 8.4 Cloud
- ASR is batch-only (no streaming), and its language list isn't published.
- Low concurrency until you prepay ($100 for 15 slots, $1,000 for 50).
- SDKs lag the API (the Python SDK defaults to `s2-pro`, the JS SDK to `s1`), and several docs pages are stale.

### 8.5 Real-world performance (GitHub issues and PRs)

**Speed: the native PyTorch path is slow**
- PR #1312 (2026-09-16) stopped decode from attending over all 32,768 KV slots. On a GV100:
  - eager went from 2.73 to 12.57 tok/s;
  - **compiled went from 16.65 to 32.74 tok/s (≈RTF 0.66)**;
  - peak memory dropped to **15.16 GB reserved**.
  - Anything before September 2026 is much slower: "10 min for one sentence" on a 4090 under Windows (#1168), 6 s/it on a 3060 (#1212).
- Windows lacks Triton, so it's much slower; use WSL2.
- **Apple Silicon:** an M4 Pro 48 GB on MPS gets **8.31 frames/s ≈ 0.39× real-time**. It works, but slower than playback.
- DGX Spark: 4 min 45 s per sentence without `--compile`, 13 s with it (#1262).

**VRAM**
- Since #1312, about 15 GB fits on 16 GB cards in principle.
- Earlier reports of 12–16 GB cards failing even with w4a16 (#1168).
- Loading goes through system RAM first, so 16 GB of RAM can OOM (#1258).
- There's a 2×16 GB split guide (D#1264).

**Quality gap: local vs web demo**
- Users report local output is noticeably worse (D#1217), and emotion tags are weak or intermittent (#1162, #1280).
- Fish attributes this to its closed text-normalization frontend, audio enhancement and tuned sampling. The weights themselves are reportedly identical.

**Benchmark caveats (confirmed by maintainers)**
- **Seed-TTS-Eval** WERs were measured on the *online engine*, which uses different normalization (#1268).
- **EmergentTTS-Eval** used the open weights, *plus* the online normalization frontend, Gemini-3-Pro-rewritten instruction tags, and curated high-quality reference audio (#1253).
- Expect worse numbers from a plain local run.

**Languages**
- Vietnamese is mispronounced (#1294). Punjabi in Gurmukhi script is poor; romanized text works better (#1321).
- With a Japanese reference, Chinese text gets read with Japanese pronunciation, and there's **no `language` parameter** to override it (#1263).
- Strong accent carry-over in cross-lingual cloning (D#1333).

**Cloning**
- Very sensitive to the reference clip.
- No stable default voice without a reference, even with a fixed seed (#1260).
- Running without a reference can hit `max_new_tokens` and produce near-silence (#1346).

**Fine-tuning**
- Past bugs include LoRA wiping weights (#1163, fixed), a crash with tied embeddings (#1195), and no resume (#1295).
- Free-running output can collapse even while the loss improves (#1346).
- What the community found works: **LoRA on the Fast AR only**, which is the repo's `r_32_alpha_16_fast` config (D#1234).
- Codec/tokenizer training code is not released (#1284).

**Maintenance**
- A stale bot closes issues after 44 days, so "closed" ≠ fixed.
- The code license switched from Apache-2.0 (≤ v1.5.1) to the Research License with S2.

### 8.6 Independent leaderboards (snapshot as of 2026-10)

| Leaderboard | Fish placement | Reference points |
|---|---|---|
| Artificial Analysis Speech Arena | S2.1 Pro: Elo 1141 (≈#24–27 of 98). **S2 Pro (open): 1117 (#33).** S1: 1082. | Eleven v4 Turbo #1 at 1334; MiniMax Speech 2.8 HD 1173; OpenAI TTS-1 HD 1103 |
| TTS Arena V2 | "OpenAudio S2" (API): #16, Elo 1520, 50% win rate | #1 CastleFlow 1561, MiniMax 2.8 HD 1540, Eleven v3 1501 |
| Fish's own blind test | S2 Pro beat ElevenLabs v3 60/40 (581 pairs) | Run by Fish; OpenAI/Cartesia/Google not included; predates Eleven v4 |

**Bottom line:** Fish is a strong upper-mid open-weights option and among the best *open* multilingual TTS models. In independent arenas it is **not** at the top overall.

---

## 9. Fish S2 vs "AUK" (Tencent Hunyuan **AuK**, open-sourced 2026-09-09)

**Assumption:** I'm taking "AUK" to mean **Tencent AuK** (arXiv 2609.08936; `tencent/AuK` and `tencent/AuK-Flash` on Hugging Face).
- It's the only speech model by that name.
- It's a 1.5B rectified-flow diffusion transformer (MMDiT + DiT) with a Qwen2.5-Omni-3B encoder and an audio VAE.
- One instruction interface covers zero-shot/instruct TTS, content/lyric editing, pitch/speed/volume, emotion/timbre/de-accent/nonverbal editing, enhancement and separation.

| | **Fish S2-Pro / S2.1-Pro** | **Tencent AuK / AuK-Flash** |
|---|---|---|
| Paradigm | Autoregressive LLM (Dual-AR) over codec tokens | Non-autoregressive flow-matching diffusion over VAE latents |
| **Streaming** | **Yes.** About 100 ms TTFA (SGLang, H200); S2.1 70–90 ms [vendor]. WebSocket API for incremental LLM text. | **No.** Generates the whole clip, and **you must pass `gen_seconds`** (target duration). No latency figures published. |
| **Languages** | **80+ / 83** | **English and Chinese** documented |
| Expressive control | Inline free-form `[tags]` at word/sub-word level, mid-sentence | Natural-language instruction per utterance (voice design without a reference) |
| Multi-speaker, long-form | Native `<|speaker:N|>` dialogue and multi-turn context, up to 32k tokens | Single utterance. ComfyUI node caps source+target at 30 s. |
| **Editing existing audio** | **No** | **Yes:** replace/insert/delete words, pitch, speed, emotion, de-accent, add/remove laughs |
| **Enhancement / separation** | **No** | **Yes:** denoise, dereverb, speaker/music separation, target-speaker extraction |
| Accuracy (self-reported) | Seed-TTS WER 0.54 zh / 0.99 en (best reported) | Seed-TTS avg WER 2.65 vs Qwen3-TTS 3.07 (a different averaging, so **not directly comparable**) |
| Cloning reference | 10–30 s + transcript | Short clip (about 5 s in examples) |
| Size / VRAM | ~4.56B; about 16 GB static, 24 GB recommended | 1.5B DiT + 3B encoder + VAE; **25 GiB peak (17 GiB with CPU offload)** on A800 |
| Apple Silicon | MPS auto-detected (unbenchmarked) | **Official MLX branch** |
| Serving | SGLang-Omni, vLLM-Omni, hosted API, LiveKit/Pipecat plugins | Research code + Gradio + ComfyUI. No hosted API or serving engine. |
| **License** | Weights **non-commercial**; commercial use via paid API or a written license | AuK weights **MIT**, **but** the required Qwen2.5-Omni-3B encoder is under the **`qwen-research`** license. Have the full stack legally reviewed before commercial use. |

**Fish's advantages over AuK, in short:**
1. Real-time streaming suitable for voice agents.
2. About 40× the language coverage.
3. Native multi-speaker, long-form and multi-turn generation.
4. Fine-grained inline emotion placement.
5. Duration comes out naturally; you don't have to guess it.
6. Production serving stacks and a hosted commercial API with SDKs and agent integrations.
7. Stronger published WER numbers.

**Pick AuK instead when:**
- the task is *editing* or *cleaning* existing speech (fix a word in a recording, change emotion, denoise, separate speakers);
- you need EN/ZH only and want MIT-licensed weights;
- you're on a Mac with MLX.

**A strong hackathon combination:** AuK for enhancing or editing user audio, then Fish for live expressive TTS.

---

## 10. Other alternatives at a glance

| Need | Strong options besides Fish |
|---|---|
| Commercial-friendly open TTS | Qwen3-TTS (Apache-2.0, 0.6B/1.7B, 10 languages, **3 s** cloning, 97 ms), CosyVoice 3 (Apache), Chatterbox (MIT, watermark), Kyutai TTS / Pocket TTS (CC-BY), Kokoro-82M (Apache, no cloning) |
| Closed TTS, top quality | ElevenLabs v4 / v4 Turbo (90+ languages, 10 s clone, ~150 ms), MiniMax Speech-2.8, Cartesia Sonic 3.6, OpenAI gpt-4o-mini-tts |
| Streaming ASR | Deepgram Nova-3, ElevenLabs Scribe v2 Realtime, Kyutai STT, Qwen3-ASR (Apache, streaming + offline) |
| Full-duplex S2S | Kyutai Moshi, NVIDIA PersonaPlex-7B, MiniCPM-o 4.5, OpenAI GPT-Live-1 / gpt-realtime-2 |

---

## 11. Hackathon recommendations

1. **Use the cloud API with `model: s2.1-pro-free`.**
   - It's free until Nov 30, needs no GPU, gives the best quality, and allows commercial-ish demos.
   - Keep the open S2-Pro for offline or research experiments on a rented 24 GB+ GPU.
2. **For a voice agent:** stream ASR (Deepgram, Kyutai or Qwen3-ASR) → LLM (stream tokens) → **Fish WebSocket TTS** (`flush` at sentence ends, `latency: "balanced"`, `pcm` at 16/24 kHz).
   - Wire it up quickly with Pipecat (`FishAudioTTSService`) or LiveKit (`fishaudio.TTS`).
   - Or use **Fish Agents** ($0.06/min) if a hosted cascaded agent is acceptable.
3. **Cloning:** 2–3 clean clips of 15–20 s with exact transcripts. Create a persistent voice via `POST /model` and reuse its `_id`.
4. **Expressiveness:** put `[emotion]` at the start of sentences, sound effects (`[laugh]`, `[sigh]`) inline, and at most 3 cues together.
5. **If you self-host:**
   - Wrap sentences in `<|speaker:0|>` for streaming.
   - Raise `max_new_tokens`, set `use_memory_cache: "on"`, and pass `--compile`.
   - Tag multiple same-speaker references as `<|speaker:0|>`.
   - Use SGLang-Omni or vLLM-Omni if you need more than one concurrent stream.
   - Budget for slower-than-real-time on Macs and consumer GPUs without `--compile`.
   - Always use a clean reference clip; it's the biggest single quality factor.

---

## 12. Sources

**Code and weights**
- github.com/fishaudio/fish-speech (main @ 214da3c; tags v1.5.1; PRs #650, #920, #986, #1016)
- huggingface.co/fishaudio/s2-pro (config.json, model.safetensors.index.json, chat_template.jinja)

**Papers**
- arXiv 2603.08823 (S2 Technical Report)
- arXiv 2411.01156 (Fish-Speech 1.4)

**Fish cloud docs**
- docs.fish.audio: OpenAPI `api-reference/openapi.json`, AsyncAPI `api-reference/asyncapi.yml`
- models-overview, pricing-and-rate-limits, voice-cloning, emotions, agents/*, compat/*
- fish.audio/blog/s2-1-pro-free-api, fish.audio/terms, fish.audio/plan
- pypi.org/project/fish-audio-sdk, npmjs.com/package/fish-audio

**AuK**
- huggingface.co/tencent/AuK, github.com/Tencent-Hunyuan/AuK, arXiv 2609.08936
- huggingface.co/Qwen/Qwen2.5-Omni-3B (license)

**GitHub issues and PRs** (fishaudio/fish-speech)
- #1162, #1168, #1212, #1253, #1258, #1260, #1262, #1263, #1268, #1272, #1280, #1294, #1295, #1312, #1321, #1346
- Discussions D#1217, D#1234, D#1264

**Serving**
- github.com/sgl-project/sglang-omni (models/fishaudio_s2_pro)
- github.com/vllm-project/vllm-omni (recipes/fishaudio/Fish-Speech-S2-Pro.md; PRs #2515, #3323)

**Leaderboards**
- artificialanalysis.ai/text-to-speech/leaderboard
- huggingface.co/spaces/TTS-AGI/TTS-Arena-V2

**Funding / roadmap**
- fish.audio/blog/fish-audio-52m-seed-funding
- cxfoundation.com (Rissa Cao interview, Aug 2026)

**Comparisons**
- github.com/QwenLM/Qwen3-TTS, Qwen3-ASR
- github.com/kyutai-labs/moshi, delayed-streams-modeling
- huggingface.co/nvidia/personaplex-7b-v1
- elevenlabs.io/blog/eleven-v4
- github.com/resemble-ai/chatterbox
