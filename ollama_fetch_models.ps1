# powershell or windows command shell
# mgua@tomware.it
# dec 2024
# see https://github.com/ollama/ollama/issues/2551 to define and alternate folder for ollama models
# (set the environmental variable OLLAMA_MODELS pointing to the folder, then reboot, then run this file)
# to set env variable: Open Windows Settings/System/About/Advanced System Settings/Advanced/ENV vars/new/system variables
# set OLLAMA_MODELS=d:\OLLAMA_MODELS or whatever. Do not end with "\"
#

# from meta, generic
ollama pull llama3.2:3b

# from meta, vision
ollama pull llama3.2-vision:11b

# from alibaba, for coding
ollama pull qwen2.5-coder:14b

# the largest instruct from meta we can afford (instruction sequences)
ollama pull llama3.1:8b-instruct-fp16

# google gemma2 small
ollama pull gemma2:2b

# google gemma2
ollama pull gemma2:27b

# from mistral and nvidia
ollama pull mistral-nemo

# vision, fast and small
ollama pull minicpm-v

# for embedding
ollama pull nomic-embed-text

# from microsoft. llama3.2 competitor
ollama pull phi3:14b

# no filters, but old
ollama pull llama2-uncensored:7b

# big, from cohere
ollama pull command-r

# coding from ibm
ollama pull granite-code:20b

# small from huggingface
ollama pull smollm:1.7b

# coding
ollama pull codegeex4:9b-all-fp16

# translation
ollama pull aya:35b-23-q3_K_S
ollama pull aya:8b

# sophisticated vision
ollama pull bakllava:7b-v1-fp16

# the long context 1M token
ollama pull llama3-gradient:8b-instruct-1048k-q8_0

# economy training
ollama pull deepseek-v2:16b-lite-chat-q8_0
