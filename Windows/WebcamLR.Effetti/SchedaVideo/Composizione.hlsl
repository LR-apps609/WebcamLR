// Qualità 5: la composizione dello sfondo sulla scheda video (Direct3D 11, compute shader cs_5_0).
// Compilato all'avvio con D3DCompile (d3dcompiler_47.dll, in Windows 10 e 11): nessun .cso nella repository.
//
// È il passo a piena risoluzione di ComposizioneProcessore (Motore/Composizione.cs), con gli stessi conti di
// RegoleBordo.Canale: bordo pulito dal vecchio sfondo, calore, light wrap, miscela con il fondo. Le cose piccole (alfa,
// fondo sfocato, colore dell'interno della persona, sfondo nuovo sfocato, maschera morbida) arrivano già pronte dal
// processore. Se cambia un numero qui, va cambiato anche in RegoleBordo (e viceversa): ComposizioneSchedaVideo.Verifica
// confronta le due all'apertura e, se differiscono, resta il processore.
//
// Le texture a colori sono R8G8B8A8_UNORM con dentro i byte BGRA del motore: .r = B, .g = G, .b = R. I conti valgono
// canale per canale, quindi l'ordine non conta; si scrive nello stesso ordine.

Texture2D<float4> Sorgente : register(t0);        // il fotogramma, piena misura
Texture2D<float> Alfa : register(t1);             // maschera rifinita, metà o un quarto
Texture2D<float4> Fondo : register(t2);           // sostituito: piena misura; sfocato: piccolo
Texture2D<float4> ColorePersona : register(t3);   // bordo pulito: colore dell'interno, piccolo
Texture2D<float4> SfondoMorbido : register(t4);   // light wrap: sfondo nuovo sfocato, piccolo
Texture2D<float> MascheraMorbida : register(t5);  // light wrap: maschera sfocata, piccola
Texture2D<float4> Calore : register(t6);          // 256×1: tabelle del calore (.r per B, .g per G, .b per R)
RWTexture2D<unorm float4> Uscita : register(u0);  // piena misura
SamplerState Lineare : register(s0);              // bilineare, bordi ripetuti (come Elaborazione.Campionamento)

cbuffer Parametri : register(b0)
{
    uint Larghezza;
    uint Altezza;
    uint Opzioni;
    uint Riservato;
};

static const uint PULITO = 1u;
static const uint LUCE = 2u;
static const uint CALORE = 4u;

// RegoleBordo.Fiducia
float Fiducia(float alfa) { return saturate(2.5 * alfa - 1.5); }

// RegoleBordo.PesoLuce
float PesoLuce(float alfa, float alfaMorbido) { return min(0.3 * alfa * (1.0 - alfaMorbido), 0.15); }

// RegoleBordo.Schermo, per tre canali (valori 0..255)
float3 Schermo(float3 a, float3 b) { return 255.0 - (255.0 - a) * (255.0 - b) / 255.0; }

[numthreads(16, 16, 1)]
void Componi(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= Larghezza || id.y >= Altezza) return;
    // Il centro del pixel in coordinate normalizzate: il campionatore bilineare con i bordi ripetuti fa
    // p = (i + 0,5) · scala − 0,5 tra 0 e n − 1, come Elaborazione.Campionamento sul processore.
    float2 uv = (float2(id.xy) + 0.5) / float2(Larghezza, Altezza);
    float3 p = Sorgente.Load(int3(id.xy, 0)).rgb * 255.0;
    float alfa = Alfa.SampleLevel(Lineare, uv, 0);
    float3 fondo = Fondo.SampleLevel(Lineare, uv, 0).rgb * 255.0;

    if (Opzioni & PULITO)
    {
        float f = Fiducia(alfa);
        float3 c = ColorePersona.SampleLevel(Lineare, uv, 0).rgb * 255.0;
        p = p * f + c * (1.0 - f);
    }
    if (Opzioni & CALORE)
    {
        uint3 i = (uint3)clamp(p + 0.5, 0.0, 255.0);
        p = float3(Calore.Load(int3(i.x, 0, 0)).r, Calore.Load(int3(i.y, 0, 0)).g, Calore.Load(int3(i.z, 0, 0)).b) * 255.0;
    }
    if (Opzioni & LUCE)
    {
        float w = PesoLuce(alfa, MascheraMorbida.SampleLevel(Lineare, uv, 0));
        float3 s = SfondoMorbido.SampleLevel(Lineare, uv, 0).rgb * 255.0;
        p += (Schermo(s, p) - p) * w;
    }
    float3 r = p * alfa + fondo * (1.0 - alfa);
    Uscita[id.xy] = float4(floor(clamp(r, 0.0, 255.0) + 0.5) / 255.0, 1.0);
}
