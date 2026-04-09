/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_RALPH_ENGINE: 'claude' | 'codex' | 'kimi'
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
