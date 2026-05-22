//+------------------------------------------------------------------+
//|                                                 RagheeHorner.mq5 |
//|                                  Copyright © 2026, EarnForex.com |
//|                                        https://www.earnforex.com |
//|                         Based on Raghee Horner's trading method. |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2026, EarnForex.com"
#property link      "https://www.earnforex.com/indicators/Raghee-Horner/"
#property version   "1.00"

#property description "Raghee Horner's 34EMA Wave and GRaB (Green-Red-Blue) Candles. Supports MTF."

#property indicator_chart_window
#property indicator_buffers 15
#property indicator_plots   6

// Plot 1: Bullish-trend candles (DRAW_CANDLES uses 4 OHLC buffers; 3 colors = outline, bullish body, bearish body).
#property indicator_label1  "Bullish (Green)"
#property indicator_type1   DRAW_CANDLES
#property indicator_color1  clrLimeGreen, clrLimeGreen, clrBlack
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

// Plot 2: Bearish-trend candles.
#property indicator_label2  "Bearish (Red)"
#property indicator_type2   DRAW_CANDLES
#property indicator_color2  clrRed, clrRed, clrBlack
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

// Plot 3: Neutral-trend candles.
#property indicator_label3  "Neutral (Blue)"
#property indicator_type3   DRAW_CANDLES
#property indicator_color3  clrDodgerBlue, clrDodgerBlue, clrBlack
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

// Plots 4-6: 34EMA Wave.
#property indicator_label4  "34EMA High"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrAqua
#property indicator_label5  "34EMA Close"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrGoldenrod
#property indicator_label6  "34EMA Low"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrMagenta

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
input color                GreenCandleColor   = clrLimeGreen;   // Green (Bullish trend) Color
input color                RedCandleColor     = clrRed;         // Red (Bearish trend) Color
input color                BlueCandleColor    = clrDodgerBlue;  // Blue (Neutral trend) Color
input color                BearishBodyColor   = clrBlack;       // Bearish (close<open) Body Color
input bool                 BullishAlerts      = false;          // Alert on a new Bullish (Green) candle
input bool                 BearishAlerts      = false;          // Alert on a new Bearish (Red) candle
input bool                 NeutralAlerts      = false;          // Alert on a new Neutral (Blue) candle
input enum_candle_to_check TriggerCandle      = Previous;       // Trigger candle for alerts
input bool                 EnableNativeAlerts = false;          // Enable Native Pop-Up Alerts
input bool                 EnableEmailAlerts  = false;          // Enable Email Alerts
input bool                 EnablePushAlerts   = false;          // Enable Push Alerts
input bool                 EnableSoundAlerts  = false;          // Enable Sound Alerts
input string               SoundFile          = "alert.wav";    // Sound file name

// GRaB candle buffers - 4 OHLC per trend color (3 trends = 12 buffers).
double GreenOpen[], GreenHigh[], GreenLow[], GreenClose[];
double RedOpen[],   RedHigh[],   RedLow[],   RedClose[];
double BlueOpen[],  BlueHigh[],  BlueLow[],  BlueClose[];
// 34EMA Wave (Plots 4-6).
double EMA_HighBuf[], EMA_CloseBuf[], EMA_LowBuf[];

// iMA handles - in MT5 iMA returns a handle; values are read via CopyBuffer.
int iMA_HighHandle  = INVALID_HANDLE;
int iMA_CloseHandle = INVALID_HANDLE;
int iMA_LowHandle   = INVALID_HANDLE;

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

int OnInit()
{
    // Resolve MTF: a higher requested TF enables MTF mode; equal or lower falls back to the chart TF.
    if (TimeFrame <= _Period)
    {
        MTF_Period    = (ENUM_TIMEFRAMES)_Period;
        MTF_Mode      = false;
        TF_Multiplier = 1;
        MTF_Suffix    = "";
    }
    else
    {
        MTF_Period    = TimeFrame;
        MTF_Mode      = true;
        TF_Multiplier = (int)(PeriodSeconds(TimeFrame) / PeriodSeconds());
        MTF_Suffix    = " " + GetTimeFrameString(MTF_Period);
    }

    // Plots 0-2: GRaB candles - 4 OHLC buffers per plot.
    SetIndexBuffer(0,  GreenOpen,    INDICATOR_DATA);
    SetIndexBuffer(1,  GreenHigh,    INDICATOR_DATA);
    SetIndexBuffer(2,  GreenLow,     INDICATOR_DATA);
    SetIndexBuffer(3,  GreenClose,   INDICATOR_DATA);
    SetIndexBuffer(4,  RedOpen,      INDICATOR_DATA);
    SetIndexBuffer(5,  RedHigh,      INDICATOR_DATA);
    SetIndexBuffer(6,  RedLow,       INDICATOR_DATA);
    SetIndexBuffer(7,  RedClose,     INDICATOR_DATA);
    SetIndexBuffer(8,  BlueOpen,     INDICATOR_DATA);
    SetIndexBuffer(9,  BlueHigh,     INDICATOR_DATA);
    SetIndexBuffer(10, BlueLow,      INDICATOR_DATA);
    SetIndexBuffer(11, BlueClose,    INDICATOR_DATA);

    // Plots 3-5: 34EMA Wave.
    SetIndexBuffer(12, EMA_HighBuf,  INDICATOR_DATA);
    SetIndexBuffer(13, EMA_CloseBuf, INDICATOR_DATA);
    SetIndexBuffer(14, EMA_LowBuf,   INDICATOR_DATA);

    // Non-series indexing throughout: index k always refers to the LTF bar at non-series position k, no shifting on new bars.
    ArraySetAsSeries(GreenOpen,     false); ArraySetAsSeries(GreenHigh,    false);
    ArraySetAsSeries(GreenLow,      false); ArraySetAsSeries(GreenClose,   false);
    ArraySetAsSeries(RedOpen,       false); ArraySetAsSeries(RedHigh,      false);
    ArraySetAsSeries(RedLow,        false); ArraySetAsSeries(RedClose,     false);
    ArraySetAsSeries(BlueOpen,      false); ArraySetAsSeries(BlueHigh,     false);
    ArraySetAsSeries(BlueLow,       false); ArraySetAsSeries(BlueClose,    false);
    ArraySetAsSeries(EMA_HighBuf,   false);
    ArraySetAsSeries(EMA_CloseBuf,  false);
    ArraySetAsSeries(EMA_LowBuf,    false);

    // Apply user color/visibility choices to the candle plots. Each DRAW_CANDLES plot uses 3 colors: outline, bullish body, bearish body.
    int candle_type = ShowGRaBCandles ? DRAW_CANDLES : DRAW_NONE;
    ConfigureCandlePlot(0, candle_type, GreenCandleColor);
    ConfigureCandlePlot(1, candle_type, RedCandleColor);
    ConfigureCandlePlot(2, candle_type, BlueCandleColor);

    // EMA Wave plots.
    int wave_type = ShowEMAWave ? DRAW_LINE : DRAW_NONE;
    PlotIndexSetInteger(3, PLOT_DRAW_TYPE,  wave_type);
    PlotIndexSetInteger(3, PLOT_LINE_COLOR, EMAHighColor);
    PlotIndexSetInteger(4, PLOT_DRAW_TYPE,  wave_type);
    PlotIndexSetInteger(4, PLOT_LINE_COLOR, EMACloseColor);
    PlotIndexSetInteger(5, PLOT_DRAW_TYPE,  wave_type);
    PlotIndexSetInteger(5, PLOT_LINE_COLOR, EMALowColor);

    // Hide values on bars too old to have a valid EMA lookback (scaled for MTF).
    int draw_begin = MTF_Mode ? EMA_Period * TF_Multiplier : EMA_Period;
    for (int n = 0; n < 6; n++) PlotIndexSetInteger(n, PLOT_DRAW_BEGIN, draw_begin);

    // Create iMA handles on MTF_Period (== _Period in non-MTF mode).
    iMA_HighHandle  = iMA(_Symbol, MTF_Period, EMA_Period, 0, MA_Mode, PRICE_HIGH);
    iMA_CloseHandle = iMA(_Symbol, MTF_Period, EMA_Period, 0, MA_Mode, PRICE_CLOSE);
    iMA_LowHandle   = iMA(_Symbol, MTF_Period, EMA_Period, 0, MA_Mode, PRICE_LOW);
    if (iMA_HighHandle == INVALID_HANDLE || iMA_CloseHandle == INVALID_HANDLE || iMA_LowHandle == INVALID_HANDLE)
    {
        Print("Failed to create iMA handle(s) on ", EnumToString(MTF_Period), ".");
        return INIT_FAILED;
    }

    IndicatorSetString (INDICATOR_SHORTNAME, "RagheeHorner(" + IntegerToString(EMA_Period) + ")" + MTF_Suffix);
    IndicatorSetInteger(INDICATOR_DIGITS,    _Digits);

    LastBullishAlertBarTime = 0;
    LastBearishAlertBarTime = 0;
    LastNeutralAlertBarTime = 0;
    AlertsInitialized       = false;
    UpperRT                 = 0;
    NewCandleTime           = 0;

    return INIT_SUCCEEDED;
}

// Configure one DRAW_CANDLES plot: outline + bullish body = trend color; bearish body = BearishBodyColor.
void ConfigureCandlePlot(int plot_idx, int draw_type, color trend_color)
{
    PlotIndexSetInteger(plot_idx, PLOT_DRAW_TYPE,     draw_type);
    PlotIndexSetInteger(plot_idx, PLOT_COLOR_INDEXES, 3);
    PlotIndexSetInteger(plot_idx, PLOT_LINE_COLOR, 0, trend_color);      // Outline + wicks.
    PlotIndexSetInteger(plot_idx, PLOT_LINE_COLOR, 1, trend_color);      // Bullish body (close > open): full color.
    PlotIndexSetInteger(plot_idx, PLOT_LINE_COLOR, 2, BearishBodyColor); // Bearish body (close < open): black by default.
}

void OnDeinit(const int reason)
{
    if (iMA_HighHandle  != INVALID_HANDLE) IndicatorRelease(iMA_HighHandle);
    if (iMA_CloseHandle != INVALID_HANDLE) IndicatorRelease(iMA_CloseHandle);
    if (iMA_LowHandle   != INVALID_HANDLE) IndicatorRelease(iMA_LowHandle);
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

    // MQL5 already defaults parameter arrays to non-series, but being explicit keeps indexing unambiguous.
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
        mtf_bars = iBars(_Symbol, MTF_Period);
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

    // On a full reset, clear all plotted buffers - any bar we don't process below should not draw.
    if (fullReset)
    {
        ArrayInitialize(GreenOpen,    EMPTY_VALUE); ArrayInitialize(GreenHigh,   EMPTY_VALUE);
        ArrayInitialize(GreenLow,     EMPTY_VALUE); ArrayInitialize(GreenClose,  EMPTY_VALUE);
        ArrayInitialize(RedOpen,      EMPTY_VALUE); ArrayInitialize(RedHigh,     EMPTY_VALUE);
        ArrayInitialize(RedLow,       EMPTY_VALUE); ArrayInitialize(RedClose,    EMPTY_VALUE);
        ArrayInitialize(BlueOpen,     EMPTY_VALUE); ArrayInitialize(BlueHigh,    EMPTY_VALUE);
        ArrayInitialize(BlueLow,      EMPTY_VALUE); ArrayInitialize(BlueClose,   EMPTY_VALUE);
        ArrayInitialize(EMA_HighBuf,  EMPTY_VALUE);
        ArrayInitialize(EMA_CloseBuf, EMPTY_VALUE);
        ArrayInitialize(EMA_LowBuf,   EMPTY_VALUE);
    }

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

    // CountBars cap (scaled for MTF). Older bars stay at EMPTY_VALUE and don't draw.
    int ltf_oldest = 0;
    if (CountBars > 0)
    {
        ltf_oldest = rates_total - (MTF_Mode ? CountBars * TF_Multiplier : CountBars);
        if (ltf_oldest < 0) ltf_oldest = 0;
        if (start_from < ltf_oldest) start_from = ltf_oldest;
    }

    // HTF-boundary tracking: cached values survive across non-advance iterations so consecutive LTF bars inside one HTF share state.
    int    prev_mtf_shift = -1;
    double cached_ema_h = 0, cached_ema_c = 0, cached_ema_l = 0;
    int    cached_color = -1; // 0=Green, 1=Red, 2=Blue.

    // Resume from buffers when we're not at the oldest end - the LTF slot at start_from-1 still holds the previous run's values.
    if (MTF_Mode && start_from > ltf_oldest)
    {
        prev_mtf_shift = iBarShiftCustom(_Symbol, MTF_Period, time[start_from - 1]);
        cached_ema_h   = EMA_HighBuf [start_from - 1];
        cached_ema_c   = EMA_CloseBuf[start_from - 1];
        cached_ema_l   = EMA_LowBuf  [start_from - 1];
        cached_color   = DecodeColor(start_from - 1);
    }

    // Scratch arrays for single-element CopyBuffer reads (iMA values).
    double ema_h_arr[1], ema_c_arr[1], ema_l_arr[1];

    // Main forward walk. Non-MTF advances every iteration; MTF advances only when entering a new HTF bar.
    for (int i = start_from; i < rates_total; i++)
    {
        int  mtf_shift = 0;
        bool advance;

        if (MTF_Mode)
        {
            mtf_shift = iBarShiftCustom(_Symbol, MTF_Period, time[i]);
            advance   = (mtf_shift != prev_mtf_shift) || (i == 0);
            prev_mtf_shift = mtf_shift;
        }
        else
        {
            advance = true;
        }

        if (advance)
        {
            // CopyBuffer's start_pos is in as-series order (0 = newest). For MTF we read at the HTF shift; for non-MTF we convert non-series i.
            int shift = MTF_Mode ? mtf_shift : (rates_total - 1 - i);

            if (CopyBuffer(iMA_HighHandle,  0, shift, 1, ema_h_arr) != 1) return prev_calculated;
            if (CopyBuffer(iMA_CloseHandle, 0, shift, 1, ema_c_arr) != 1) return prev_calculated;
            if (CopyBuffer(iMA_LowHandle,   0, shift, 1, ema_l_arr) != 1) return prev_calculated;

            cached_ema_h = ema_h_arr[0];
            cached_ema_c = ema_c_arr[0];
            cached_ema_l = ema_l_arr[0];

            double cmp_high, cmp_low;
            if (MTF_Mode)
            {
                cmp_high = iHigh(_Symbol, MTF_Period, mtf_shift);
                cmp_low  = iLow (_Symbol, MTF_Period, mtf_shift);
            }
            else
            {
                cmp_high = high[i];
                cmp_low  = low [i];
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

        // Candle shape uses LTF OHLC even in MTF mode - chart keeps its native granularity, only the trend color comes from the HTF.
        WriteCandle(i, cached_color, open[i], high[i], low[i], close[i]);
    }

    if (MTF_Mode) UpperRT = mtf_bars;

    CheckAlerts(rates_total);

    return rates_total;
}

// Write OHLC to the trend plot matching color_idx and EMPTY_VALUE to the other two so only the matching plot draws this bar.
void WriteCandle(int i, int color_idx, double o, double h, double l, double c)
{
    GreenOpen[i] = EMPTY_VALUE; GreenHigh[i] = EMPTY_VALUE;
    GreenLow [i] = EMPTY_VALUE; GreenClose[i] = EMPTY_VALUE;
    RedOpen  [i] = EMPTY_VALUE; RedHigh  [i] = EMPTY_VALUE;
    RedLow   [i] = EMPTY_VALUE; RedClose [i] = EMPTY_VALUE;
    BlueOpen [i] = EMPTY_VALUE; BlueHigh [i] = EMPTY_VALUE;
    BlueLow  [i] = EMPTY_VALUE; BlueClose[i] = EMPTY_VALUE;

    if (color_idx == 0)
    {
        GreenOpen[i] = o; GreenHigh[i] = h;
        GreenLow [i] = l; GreenClose[i] = c;
    }
    else if (color_idx == 1)
    {
        RedOpen[i] = o; RedHigh[i] = h;
        RedLow [i] = l; RedClose[i] = c;
    }
    else if (color_idx == 2)
    {
        BlueOpen[i] = o; BlueHigh[i] = h;
        BlueLow [i] = l; BlueClose[i] = c;
    }
}

// Decode the trend color stored at LTF index i by checking which plot's close buffer is non-empty.
int DecodeColor(int i)
{
    if (GreenClose[i] != EMPTY_VALUE) return 0;
    if (RedClose  [i] != EMPTY_VALUE) return 1;
    if (BlueClose [i] != EMPTY_VALUE) return 2;
    return -1;
}

// True when a new LTF bar has opened since the previous call - used by the MTF freshness guard.
bool CheckIfNewCandle()
{
    datetime cur = iTime(_Symbol, _Period, 0);
    if (NewCandleTime == cur) return false;
    NewCandleTime = cur;
    return true;
}

// LTF (non-series) index of the first LTF bar inside HTF[htf_shift]. Returns -1 if the HTF bar isn't available in LTF history.
int FirstLTFOfHTF(int htf_shift, int rates_total)
{
    datetime htf_open = iTime(_Symbol, MTF_Period, htf_shift);
    if (htf_open <= 0) return -1;
    int ltf_as_series = iBarShiftCustom(_Symbol, _Period, htf_open);
    int idx = rates_total - 1 - ltf_as_series;
    if (idx < 0 || idx >= rates_total) return -1;
    return idx;
}

// Fire alerts on a color transition between the relevant pair of bars (LTF pair in non-MTF, HTF pair via FirstLTFOfHTF in MTF).
void CheckAlerts(int rates_total)
{
    if (!BullishAlerts && !BearishAlerts && !NeutralAlerts) return;

    int bar_count    = MTF_Mode ? iBars(_Symbol, MTF_Period) : rates_total;
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
        alertBarTime = iTime(_Symbol, MTF_Period, htf_new);
    }
    else
    {
        idxNew = (TriggerCandle == Previous) ? (rates_total - 2) : (rates_total - 1);
        idxOld = idxNew - 1;
        if (idxOld < 0) return;
        alertBarTime = iTime(_Symbol, _Period, (TriggerCandle == Previous) ? 1 : 0);
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
    if (color_new < 0 || color_old < 0) return;
    if (color_new == color_old)         return;

    // MT5's Alert popup already shows symbol/timeframe in its own columns; email and push need the context prefix.
    string context = _Symbol + " " + GetTimeFrameString(MTF_Period) + ": ";
    string mode    = (TriggerCandle == Current) ? " [current bar]" : "";

    if (BullishAlerts && color_new == 0 && LastBullishAlertBarTime != alertBarTime)
    {
        string core = "Raghee Horner: New Bullish (Green) candle" + mode + ".";
        FireAlert(core, context);
        LastBullishAlertBarTime = alertBarTime;
    }
    if (BearishAlerts && color_new == 1 && LastBearishAlertBarTime != alertBarTime)
    {
        string core = "Raghee Horner: New Bearish (Red) candle" + mode + ".";
        FireAlert(core, context);
        LastBearishAlertBarTime = alertBarTime;
    }
    if (NeutralAlerts && color_new == 2 && LastNeutralAlertBarTime != alertBarTime)
    {
        string core = "Raghee Horner: New Neutral (Blue) candle" + mode + ".";
        FireAlert(core, context);
        LastNeutralAlertBarTime = alertBarTime;
    }
}

// Dispatch an alert via every channel the user has enabled. The native Alert() popup gets the bare core because MT5's alert engine annotates each entry with symbol and timeframe; email and push travel out-of-band and need the context prefix.
void FireAlert(string core, string context)
{
    if (EnableNativeAlerts) Alert(core);
    if (EnableEmailAlerts)  SendMail("Raghee Horner Alert", context + core);
    if (EnablePushAlerts)   SendNotification(context + core);
    if (EnableSoundAlerts)  PlaySound(SoundFile);
}

string GetTimeFrameString(ENUM_TIMEFRAMES period)
{
    return StringSubstr(EnumToString((ENUM_TIMEFRAMES)period), 7);
}

// iBarShift with a custom fallback search for when the standard call returns -1 (HTF data not yet available).
int iBarShiftCustom(string symbol, ENUM_TIMEFRAMES tf, datetime time) // Always exact = false.
{
    int i = iBarShift(symbol, tf, time);
    if (i >= 0) return i;
    i = 0;
    int bars = iBars(symbol, tf);
    while (iTime(symbol, tf, i) > time)
    {
        i++;
        if (i >= bars) return -1;
    }
    return i;
}
//+------------------------------------------------------------------+