// Cloudflare Worker giriş noktası. İş mantığı aktarici.js'te.
// ⚠️ Burada YALNIZ varsayılan dışa aktarım var: Workers, ana modülün
// adlandırılmış dışa aktarımlarını Durable Object / giriş noktası sanabilir;
// testlerin kullandığı yardımcılar (onbellegiSifirla) bu yüzden ayrı modülde.
import { isle } from './aktarici.js';

export default {
  fetch: (istek, env) => isle(istek, env),
};
