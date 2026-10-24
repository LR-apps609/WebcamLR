using System.Runtime.InteropServices;
using static WebcamLR.Webcam.DirectShow.ComNativo;

namespace WebcamLR.Webcam.DirectShow;

/// <summary>IEnumPins del filtro: un solo pin, «Cattura».</summary>
[ClassInterface(ClassInterfaceType.None)]
public sealed unsafe class EnumeratorePin : IEnumPins
{
    private readonly PinWebcam pin;
    private int posizione;

    internal EnumeratorePin(PinWebcam pin, int posizione = 0)
    {
        this.pin = pin;
        this.posizione = posizione;
    }

    public int Next(uint cPins, nint ppPins, nint pcFetched)
    {
        if (ppPins == 0) return E_POINTER;
        if (cPins != 1 && pcFetched == 0) return E_POINTER;
        uint dati = 0;
        try
        {
            while (dati < cPins && posizione < 1)
            {
                ((nint*)ppPins)[dati] = Marshal.GetComInterfaceForObject(pin, typeof(IPin));
                dati++;
                posizione++;
            }
        }
        catch (Exception) { return E_FAIL; }
        if (pcFetched != 0) *(uint*)pcFetched = dati;
        return dati == cPins ? S_OK : S_FALSE;
    }

    public int Skip(uint cPins)
    {
        posizione += (int)Math.Min(cPins, 2);
        return posizione <= 1 ? S_OK : S_FALSE;
    }

    public int Reset()
    {
        posizione = 0;
        return S_OK;
    }

    public int Clone(nint ppEnum)
    {
        if (ppEnum == 0) return E_POINTER;
        try
        {
            *(nint*)ppEnum = Marshal.GetComInterfaceForObject(new EnumeratorePin(pin, posizione), typeof(IEnumPins));
            return S_OK;
        }
        catch (Exception) { return E_FAIL; }
    }
}

/// <summary>IEnumMediaTypes del pin: i formati di <see cref="FormatiDirectShow"/>, quello scelto (se c'è) per primo.</summary>
[ClassInterface(ClassInterfaceType.None)]
public sealed unsafe class EnumeratoreTipi : IEnumMediaTypes
{
    private readonly FormatoDirectShow[] formati;
    private int posizione;

    internal EnumeratoreTipi(FormatoDirectShow[] formati, int posizione = 0)
    {
        this.formati = formati;
        this.posizione = posizione;
    }

    public int Next(uint cMediaTypes, nint ppMediaTypes, nint pcFetched)
    {
        if (ppMediaTypes == 0) return E_POINTER;
        if (cMediaTypes != 1 && pcFetched == 0) return E_POINTER;
        uint dati = 0;
        try
        {
            while (dati < cMediaTypes && posizione < formati.Length)
            {
                ((AM_MEDIA_TYPE**)ppMediaTypes)[dati] = TipoMedia.Crea(formati[posizione]);
                dati++;
                posizione++;
            }
        }
        catch (Exception) { return E_OUTOFMEMORY; }
        if (pcFetched != 0) *(uint*)pcFetched = dati;
        return dati == cMediaTypes ? S_OK : S_FALSE;
    }

    public int Skip(uint cMediaTypes)
    {
        posizione = (int)Math.Min(formati.Length + 1L, posizione + (long)cMediaTypes);
        return posizione <= formati.Length ? S_OK : S_FALSE;
    }

    public int Reset()
    {
        posizione = 0;
        return S_OK;
    }

    public int Clone(nint ppEnum)
    {
        if (ppEnum == 0) return E_POINTER;
        try
        {
            *(nint*)ppEnum = Marshal.GetComInterfaceForObject(new EnumeratoreTipi(formati, posizione), typeof(IEnumMediaTypes));
            return S_OK;
        }
        catch (Exception) { return E_FAIL; }
    }
}
