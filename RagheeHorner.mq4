//+------------------------------------------------------------------+
//|                                                 RagheeHorner.mq4 |
//|                                  Copyright © 2026, EarnForex.com |
//|                                        https://www.earnforex.com |
//|                         Based on Raghee Horner's trading method. |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2026, EarnForex.com"
#property link      "https://www.earnforex.com/indicators/Raghee-Horner/"
#property version   "1.00"
#property strict

#property description "Raghee Horner's 34EMA Wave and GRaB (Green-Red-Blue) Candles. Supports MTF."
#property description "Tip: Hide chart: switch to Line (Alt+3), F8, Line graph color to None."

#property indicator_chart_window
#property indicator_buffers 15

enum enum_candle_to_check
{
    Current,    // Current (forming) candle
    Previous    // Previous (just-closed) candle
};

input int                  EMA_Period         = 34;             // 34EMA Wave Period
input ENUM_MA_METHOD       MA_Mode            = MODE_EMA;       // Moving Average Mode
input ENUM_TIMEFRAMES      TimeFrame          = PERIOD_CURRENT; // Timeframe (higher than chart enables MTF)
input int                  CountBars          = 5000;           // Bars to compute (0 = all)
input bool                 ShowEMAWave        = true;           // Show 34EMA Wave
input bool                 ShowGRaBCandles    = true;           // Show GRaB Candles
input color                EMAHighColor       = clrAqua;        // 34EMA High Color
input color                EMACloseColor      = clrGoldenrod;   // 34EMA Close Color
input color                EMALowColor        = clrMagenta;     // 34EMA Low Color
input color                GreenCandleColor   = clrLimeGreen;   // Green Candle Color (Bullish)
input color                RedCandleColor     = clrRed;         // Red Candle Color (Bearish)
input color                BlueCandleColor    = clrDodgerBlue;  // Blue Candle Color (Neutral)
input bool                 BullishAlerts      = false;          // Alert on a new Bullish (Green) candle
input bool                 BearishAlerts      = false;          // Alert on a new Bearish (Red) candle
input bool                 NeutralAlerts      = false;          // Alert on a new Neutral (Blue) candle
input enum_candle_to_check TriggerCandle      = Previous;       // Trigger candle for alerts
input bool                 EnableNativeAlerts = false;          // Enable Native Pop-Up Alerts
input bool                 EnableEmailAlerts  = false;          // Enable Email Alerts
input bool                 EnablePushAlerts   = false;          // Enable Push Alerts
input bool                 EnableSoundAlerts  = false;          // Enable Sound Alerts
input string               SoundFile          = "alert.wav";    // Sound file name

// Indicator buffers - 4 per GRaB color (paired wick + paired body) and 3 for the Wave:
double GreenWickHi[],  GreenWickLo[],  GreenBodyOpen[], GreenBodyClose[];
double RedWickHi[],    RedWickLo[],    RedBodyOpen[],   RedBodyClose[];
double BlueWickHi[],   BlueWickLo[],   BlueBodyOpen[],  BlueBodyClose[];
double EMA_HighBuf[],  EMA_CloseBuf[], EMA_LowBuf[];

// MTF state.
ENUM_TIMEFRAMES MTF_Period;
string          MTF_Suffix;
bool            MTF_Mode;
int             TF_Multiplier;
int             UpperRT       = 0;
datetime        NewCandleTime = 0;

// Alert dedup - one bar-time stamp per alert type prevents re-firing on the same trigger bar.
datetime LastBullishAlertBarTime = 0;
datetime LastBearishAlertBarTime = 0;
datetime LastNeutralAlertBarTime = 0;
bool     AlertsInitialized       = false;

void OnInit()
{
    // Resolve MTF: a higher requested TF enables MTF mode; equal or lower falls back to the chart TF.
    if (TimeFrame <= Period())
    {
        MTF_Period    = (ENUM_TIMEFRAMES)Period();
        MTF_Mode      = false;
        TF_Multiplier = 1;
        MTF_Suffix    = "";
    }
    else
    {
        MTF_Period    = TimeFrame;
        MTF_Mode      = true;
        TF_Multiplier = PeriodSeconds(TimeFrame) / PeriodSeconds();
        MTF_Suffix    = " " + GetTimeFrameString(MTF_Period);
    }

    // Candle buffers - paired DRAW_HISTOGRAM (wick width 1, body width 3, same color in each pair).
    int candle_style = ShowGRaBCandles ? DRAW_HISTOGRAM : DRAW_NONE;

    SetIndexBuffer(0, GreenWickHi);    SetIndexStyle(0, candle_style, STYLE_SOLID, 1, GreenCandleColor); SetIndexLabel(0, NULL);
    SetIndexBuffer(1, GreenWickLo);    SetIndexStyle(1, candle_style, STYLE_SOLID, 1, GreenCandleColor); SetIndexLabel(1, "Bullish Wick");
    SetIndexBuffer(2, GreenBodyOpen);  SetIndexStyle(2, candle_style, STYLE_SOLID, 3, GreenCandleColor); SetIndexLabel(2, NULL);
    SetIndexBuffer(3, GreenBodyClose); SetIndexStyle(3, candle_style, STYLE_SOLID, 3, GreenCandleColor); SetIndexLabel(3, "Bullish Body");

    SetIndexBuffer(4, RedWickHi);      SetIndexStyle(4, candle_style, STYLE_SOLID, 1, RedCandleColor);   SetIndexLabel(4, NULL);
    SetIndexBuffer(5, RedWickLo);      SetIndexStyle(5, candle_style, STYLE_SOLID, 1, RedCandleColor);   SetIndexLabel(5, "Bearish Wick");
    SetIndexBuffer(6, RedBodyOpen);    SetIndexStyle(6, candle_style, STYLE_SOLID, 3, RedCandleColor);   SetIndexLabel(6, NULL);
    SetIndexBuffer(7, RedBodyClose);   SetIndexStyle(7, candle_style, STYLE_SOLID, 3, RedCandleColor);   SetIndexLabel(7, "Bearish Body");

    SetIndexBuffer(8,  BlueWickHi);    SetIndexStyle(8,  candle_style, STYLE_SOLID, 1, BlueCandleColor); SetIndexLabel(8,  NULL);
    SetIndexBuffer(9,  BlueWickLo);    SetIndexStyle(9,  candle_style, STYLE_SOLID, 1, BlueCandleColor); SetIndexLabel(9,  "Neutral Wick");
    SetIndexBuffer(10, BlueBodyOpen);  SetIndexStyle(10, candle_style, STYLE_SOLID, 3, BlueCandleColor); SetIndexLabel(10, NULL);
    SetIndexBuffer(11, BlueBodyClose); SetIndexStyle(11, candle_style, STYLE_SOLID, 3, BlueCandleColor); SetIndexLabel(11, "Neutral Body");

    // 34EMA Wave lines.
    int wave_style = ShowEMAWave ? DRAW_LINE : DRAW_NONE;
    SetIndexBuffer(12, EMA_HighBuf);  SetIndexStyle(12, wave_style, STYLE_SOLID, 1, EMAHighColor);  SetIndexLabel(12, "34EMA High");
    SetIndexBuffer(13, EMA_CloseBuf); SetIndexStyle(13, wave_style, STYLE_SOLID, 1, EMACloseColor); SetIndexLabel(13, "34EMA Close");
    SetIndexBuffer(14, EMA_LowBuf);   SetIndexStyle(14, wave_style, STYLE_SOLID, 1, EMALowColor);   SetIndexLabel(14, "34EMA Low");

    // Non-series indexing throughout: index 0 = oldest, rates_total-1 = live. Values written at index k stay at k across ticks.
    ArraySetAsSeries(GreenWickHi,    false); ArraySetAsSeries(GreenWickLo,    false);
    ArraySetAsSeries(GreenBodyOpen,  false); ArraySetAsSeries(GreenBodyClose, false);
    ArraySetAsSeries(RedWickHi,      false); ArraySetAsSeries(RedWickLo,      false);
    ArraySetAsSeries(RedBodyOpen,    false); ArraySetAsSeries(RedBodyClose,   false);
    ArraySetAsSeries(BlueWickHi,     false); ArraySetAsSeries(BlueWickLo,     false);
    ArraySetAsSeries(BlueBodyOpen,   false); ArraySetAsSeries(BlueBodyClose,  false);
    ArraySetAsSeries(EMA_HighBuf,    false); ArraySetAsSeries(EMA_CloseBuf,   false);
    ArraySetAsSeries(EMA_LowBuf,     false);

    // Hide values on bars too old to have a valid EMA lookback (scaled for MTF).
    int draw_begin = MTF_Mode ? EMA_Period * TF_Multiplier : EMA_Period;
    for (int n = 0; n < 15; n++) SetIndexDrawBegin(n, draw_begin);

    IndicatorShortName("RagheeHorner(" + IntegerToString(EMA_Period) + ")" + MTF_Suffix);
    IndicatorDigits(Digits);

    LastBullishAlertBarTime = 0;
    LastBearishAlertBarTime = 0;
    LastNeutralAlertBarTime = 0;
    AlertsInitialized       = false;
    UpperRT                 = 0;
    NewCandleTime           = 0;
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    if (rates_total < EMA_Period + 1) return 0;

    // Force non-series indexing on parameter arrays - MQL4 doesn't reliably default to non-series.
    ArraySetAsSeries(time,  false);
    ArraySetAsSeries(open,  false);
    ArraySetAsSeries(high,  false);
    ArraySetAsSeries(low,   false);
    ArraySetAsSeries(close, false);

    bool isNewCandle = CheckIfNewCandle();

    // MTF freshness: full recalc if HTF history desynchronizes from the LTF.
    int mtf_bars = 0;
    if (MTF_Mode)
    {
        mtf_bars = iBars(Symbol(), MTF_Period);
        if (UpperRT != 0 &&
            ((UpperRT != mtf_bars && !isNewCandle) || // HTF advanced without LTF advancing.
             (UpperRT > mtf_bars) ||                  // HTF history shrank.
             (mtf_bars - UpperRT > 1)))               // More than one HTF bar arrived in one tick.
        {
            UpperRT = mtf_bars;
            return 0;
        }
    }

    bool fullReset = (prev_calculated == 0);

    // Starting LTF index. In MTF we back up TF_Multiplier so the whole live HTF section is redone (its iMA evolves every tick).
    int start_from;
    if (fullReset)
    {
        start_from = 0;
    }
    else
    {
        start_from = prev_calculated - 1;
        if (MTF_Mode) start_from -= TF_Multiplier;
        if (start_from < 0) start_from = 0;
    }

    // CountBars cap (scaled for MTF). Older bars are left untouched and won't show.
    int ltf_oldest = 0;
    if (CountBars > 0)
    {
        ltf_oldest = rates_total - (MTF_Mode ? CountBars * TF_Multiplier : CountBars);
        if (ltf_oldest < 0) ltf_oldest = 0;
        if (start_from < ltf_oldest) start_from = ltf_oldest;
    }

    // HTF-boundary tracking: cached_* survive across non-advance iterations so consecutive LTF bars in one HTF reuse the same EMA + color.
    int    prev_mtf_shift = -1;
    double cached_ema_h = 0, cached_ema_c = 0, cached_ema_l = 0;
    int    cached_color = -1; // 0=Green, 1=Red, 2=Blue.

    // Resume from buffers when we're not at the oldest end - the LTF slot at start_from-1 still holds the previous run's values.
    if (MTF_Mode && start_from > ltf_oldest)
    {
        prev_mtf_shift = iBarShift(Symbol(), MTF_Period, time[start_from - 1]);
        cached_ema_h   = EMA_HighBuf [start_from - 1];
        cached_ema_c   = EMA_CloseBuf[start_from - 1];
        cached_ema_l   = EMA_LowBuf  [start_from - 1];
        cached_color   = DecodeColor(start_from - 1);
    }

    // Main forward walk. Non-MTF advances every iteration; MTF advances only when entering a new HTF bar.
    for (int i = start_from; i < rates_total; i++)
    {
        int  mtf_shift = 0;
        bool advance;

        if (MTF_Mode)
        {
            mtf_shift = iBarShift(Symbol(), MTF_Period, time[i]);
            advance   = (mtf_shift != prev_mtf_shift) || (i == 0);
            prev_mtf_shift = mtf_shift;
        }
        else
        {
            advance = true;
        }

        if (advance)
        {
            double cmp_high, cmp_low;

            if (MTF_Mode)
            {
                cached_ema_h = iMA  (Symbol(), MTF_Period, EMA_Period, 0, MA_Mode, PRICE_HIGH,  mtf_shift);
                cached_ema_c = iMA  (Symbol(), MTF_Period, EMA_Period, 0, MA_Mode, PRICE_CLOSE, mtf_shift);
                cached_ema_l = iMA  (Symbol(), MTF_Period, EMA_Period, 0, MA_Mode, PRICE_LOW,   mtf_shift);
                cmp_high     = iHigh(Symbol(), MTF_Period, mtf_shift);
                cmp_low      = iLow (Symbol(), MTF_Period, mtf_shift);
            }
            else
            {
                int shift = rates_total - 1 - i; // Non-series -> as-series for iMA's bar argument.
                cached_ema_h = iMA(NULL, 0, EMA_Period, 0, MA_Mode, PRICE_HIGH,  shift);
                cached_ema_c = iMA(NULL, 0, EMA_Period, 0, MA_Mode, PRICE_CLOSE, shift);
                cached_ema_l = iMA(NULL, 0, EMA_Period, 0, MA_Mode, PRICE_LOW,   shift);
                cmp_high     = high[i];
                cmp_low      = low [i];
            }

            // Min/max of all 3 EMAs is robust during reversals when EMA(High)/EMA(Low) momentarily cross.
            double wave_top    = MathMax(cached_ema_h, MathMax(cached_ema_c, cached_ema_l));
            double wave_bottom = MathMin(cached_ema_h, MathMin(cached_ema_c, cached_ema_l));

            if      (cmp_low  > wave_top)    cached_color = 0; // GREEN: bar fully above the Wave.
            else if (cmp_high < wave_bottom) cached_color = 1; // RED: bar fully below the Wave.
            else                             cached_color = 2; // BLUE: bar overlaps the Wave.
        }

        EMA_HighBuf [i] = cached_ema_h;
        EMA_CloseBuf[i] = cached_ema_c;
        EMA_LowBuf  [i] = cached_ema_l;

        // Candle shape uses LTF OHLC even in MTF mode - chart keeps its native granularity, only the color comes from the HTF.
        WriteCandle(i, cached_color, open[i], high[i], low[i], close[i]);
    }

    if (MTF_Mode) UpperRT = mtf_bars;

    CheckAlerts(rates_total);

    return rates_total;
}

// Set the 12 GRaB candle buffers at LTF index i. Only the slot matching color_idx holds OHLC; the rest are EMPTY_VALUE.
void WriteCandle(int i, int color_idx, double o, double h, double l, double c)
{
    GreenWickHi[i]    = EMPTY_VALUE; GreenWickLo[i]    = EMPTY_VALUE;
    GreenBodyOpen[i]  = EMPTY_VALUE; GreenBodyClose[i] = EMPTY_VALUE;
    RedWickHi[i]      = EMPTY_VALUE; RedWickLo[i]      = EMPTY_VALUE;
    RedBodyOpen[i]    = EMPTY_VALUE; RedBodyClose[i]   = EMPTY_VALUE;
    BlueWickHi[i]     = EMPTY_VALUE; BlueWickLo[i]     = EMPTY_VALUE;
    BlueBodyOpen[i]   = EMPTY_VALUE; BlueBodyClose[i]  = EMPTY_VALUE;

    if (color_idx == 0)
    {
        GreenWickHi[i]   = h; GreenWickLo[i]    = l;
        GreenBodyOpen[i] = o; GreenBodyClose[i] = c;
    }
    else if (color_idx == 1)
    {
        RedWickHi[i]   = h; RedWickLo[i]    = l;
        RedBodyOpen[i] = o; RedBodyClose[i] = c;
    }
    else if (color_idx == 2)
    {
        BlueWickHi[i]   = h; BlueWickLo[i]    = l;
        BlueBodyOpen[i] = o; BlueBodyClose[i] = c;
    }
}

// Decode the GRaB color stored at LTF index i by checking which body buffer is non-empty.
int DecodeColor(int i)
{
    if (GreenBodyClose[i] != EMPTY_VALUE) return 0;
    if (RedBodyClose  [i] != EMPTY_VALUE) return 1;
    if (BlueBodyClose [i] != EMPTY_VALUE) return 2;
    return -1;
}

// LTF (non-series) index of the first LTF bar inside HTF[htf_shift]. Returns -1 if the HTF bar isn't available in LTF history.
int FirstLTFOfHTF(int htf_shift, int rates_total)
{
    datetime htf_open = iTime(Symbol(), MTF_Period, htf_shift);
    if (htf_open <= 0) return -1;
    int ltf_as_series = iBarShift(Symbol(), Period(), htf_open);
    int idx = rates_total - 1 - ltf_as_series;
    if (idx < 0 || idx >= rates_total) return -1;
    return idx;
}

// True when a new LTF bar has opened since the previous call - used by the MTF freshness guard.
bool CheckIfNewCandle()
{
    datetime cur = iTime(Symbol(), Period(), 0);
    if (NewCandleTime == cur) return false;
    NewCandleTime = cur;
    return true;
}

// Fire alerts on a color transition between the relevant pair of bars (LTF pair in non-MTF, HTF pair via FirstLTFOfHTF in MTF).
void CheckAlerts(int rates_total)
{
    if (!BullishAlerts && !BearishAlerts && !NeutralAlerts) return;

    int bar_count    = MTF_Mode ? iBars(Symbol(), MTF_Period) : rates_total;
    int min_required = (TriggerCandle == Previous) ? 3 : 2;
    if (bar_count    < min_required) return;
    if (rates_total  < min_required) return;

    int      idxNew, idxOld;
    datetime alertBarTime;

    if (MTF_Mode)
    {
        int htf_old = (TriggerCandle == Previous) ? 2 : 1;
        int htf_new = (TriggerCandle == Previous) ? 1 : 0;
        idxOld = FirstLTFOfHTF(htf_old, rates_total);
        idxNew = FirstLTFOfHTF(htf_new, rates_total);
        if (idxOld < 0 || idxNew < 0) return;
        alertBarTime = iTime(Symbol(), MTF_Period, htf_new);
    }
    else
    {
        idxNew = (TriggerCandle == Previous) ? (rates_total - 2) : (rates_total - 1);
        idxOld = idxNew - 1;
        if (idxOld < 0) return;
        alertBarTime = iTime(Symbol(), Period(), (TriggerCandle == Previous) ? 1 : 0);
    }

    // Warmup: the first OnCalculate after attach only stamps the guards so we don't fire on stale history.
    if (!AlertsInitialized)
    {
        LastBullishAlertBarTime = alertBarTime;
        LastBearishAlertBarTime = alertBarTime;
        LastNeutralAlertBarTime = alertBarTime;
        AlertsInitialized       = true;
        return;
    }

    int color_new = DecodeColor(idxNew);
    int color_old = DecodeColor(idxOld);
    if (color_new < 0 || color_old < 0)  return;
    if (color_new == color_old)          return;

    string sym  = Symbol();
    string tf   = GetTimeFrameString(MTF_Period);
    string mode = (TriggerCandle == Current) ? " [current bar]" : "";

    if (BullishAlerts && color_new == 0 && LastBullishAlertBarTime != alertBarTime)
    {
        FireAlert("Raghee Horner: " + sym + " - " + tf + " - New Bullish (Green) candle" + mode + ".");
        LastBullishAlertBarTime = alertBarTime;
    }
    if (BearishAlerts && color_new == 1 && LastBearishAlertBarTime != alertBarTime)
    {
        FireAlert("Raghee Horner: " + sym + " - " + tf + " - New Bearish (Red) candle" + mode + ".");
        LastBearishAlertBarTime = alertBarTime;
    }
    if (NeutralAlerts && color_new == 2 && LastNeutralAlertBarTime != alertBarTime)
    {
        FireAlert("Raghee Horner: " + sym + " - " + tf + " - New Neutral (Blue) candle" + mode + ".");
        LastNeutralAlertBarTime = alertBarTime;
    }
}

void FireAlert(string message)
{
    if (EnableNativeAlerts) Alert(message);
    if (EnableEmailAlerts)  SendMail("Raghee Horner Alert", message);
    if (EnablePushAlerts)   SendNotification(message);
    if (EnableSoundAlerts)  PlaySound(SoundFile);
}

string GetTimeFrameString(ENUM_TIMEFRAMES period)
{
    return StringSubstr(EnumToString(period), 7);
}
//+------------------------------------------------------------------+