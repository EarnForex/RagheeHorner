// -------------------------------------------------------------------------------
//   RagheeHorner Horner indicator with multi-timeframe support and signal alerts.
//   34EMA Wave + GRaB (Green-Red-Blue) Candles.
//
//   Version 1.00
//   Copyright 2026, EarnForex.com
//   https://www.earnforex.com/indicators/RagheeHorner-Horner/.
// -------------------------------------------------------------------------------

using System;
using cAlgo.API;
using cAlgo.API.Indicators;

namespace cAlgo.Indicators
{
    [Indicator(IsOverlay = true, TimeZone = TimeZones.UTC, AccessRights = AccessRights.None)]
    public class RagheeHorner : Indicator
    {
        public enum CandleToCheck { CurrentCandle, ClosedCandle }

        [Parameter("EMA Period", DefaultValue = 34, MinValue = 2, Group = "Main")]
        public int EMA_Period { get; set; }

        [Parameter("MA Type", DefaultValue = MovingAverageType.Exponential, Group = "Main")]
        public MovingAverageType MA_Type { get; set; }

        [Parameter("Timeframe (only higher than chart enables MTF)", Group = "Main")]
        public TimeFrame InputTimeFrame { get; set; }

        [Parameter("Show GRaB Candles", DefaultValue = true, Group = "Visuals")]
        public bool ShowGRaBCandles { get; set; }

        [Parameter("Green Color (Bullish trend)", DefaultValue = "LimeGreen", Group = "Visuals")]
        public Color GreenCandleColor { get; set; }

        [Parameter("Red Color (Bearish trend)", DefaultValue = "Red", Group = "Visuals")]
        public Color RedCandleColor { get; set; }

        [Parameter("Blue Color (Neutral trend)", DefaultValue = "DodgerBlue", Group = "Visuals")]
        public Color BlueCandleColor { get; set; }

        [Parameter("Bearish Body Color (close < open)", DefaultValue = "Black", Group = "Visuals")]
        public Color BearishBodyColor { get; set; }

        [Parameter("Alert on new Bullish (Green) candle", DefaultValue = false, Group = "Alerts")]
        public bool BullishAlerts { get; set; }

        [Parameter("Alert on new Bearish (Red) candle", DefaultValue = false, Group = "Alerts")]
        public bool BearishAlerts { get; set; }

        [Parameter("Alert on new Neutral (Blue) candle", DefaultValue = false, Group = "Alerts")]
        public bool NeutralAlerts { get; set; }

        [Parameter("Trigger Candle", DefaultValue = CandleToCheck.ClosedCandle, Group = "Alerts")]
        public CandleToCheck TriggerCandle { get; set; }

        [Parameter("Enable Native Alerts", DefaultValue = false, Group = "Alerts")]
        public bool EnableNativeAlerts { get; set; }

        [Parameter("Enable Email Alerts", DefaultValue = false, Group = "Alerts")]
        public bool EnableEmailAlerts { get; set; }

        [Parameter("Email Address", DefaultValue = "", Group = "Alerts")]
        public string EmailAddress { get; set; }

        [Parameter("Enable Sound Alerts", DefaultValue = false, Group = "Alerts")]
        public bool EnableSoundAlerts { get; set; }

        [Parameter("Sound Type", DefaultValue = SoundType.Announcement, Group = "Alerts")]
        public SoundType SoundType { get; set; }

        [Output("34EMA High", LineColor = "Aqua", LineStyle = LineStyle.Solid, PlotType = PlotType.Line, Thickness = 1)]
        public IndicatorDataSeries EMA_HighOutput { get; set; }

        [Output("34EMA Close", LineColor = "Goldenrod", LineStyle = LineStyle.Solid, PlotType = PlotType.Line, Thickness = 1)]
        public IndicatorDataSeries EMA_CloseOutput { get; set; }

        [Output("34EMA Low", LineColor = "Magenta", LineStyle = LineStyle.Solid, PlotType = PlotType.Line, Thickness = 1)]
        public IndicatorDataSeries EMA_LowOutput { get; set; }

        // Per-LTF trend classification (0=Green, 1=Red, 2=Blue, NaN=unset). Read by CheckAlerts.
        private IndicatorDataSeries MtfColor;

        // EMAs on MTF data (= chart data in non-MTF). cTrader caches these internally.
        private MovingAverage emaHigh, emaClose, emaLow;

        private Bars MtfBars;
        private bool IsMtf;

        // Alert dedup: one bar-time stamp per type, plus a warmup gate (first IsLastBar stamps but doesn't fire).
        private DateTime LastBullishAlertBarTime = DateTime.MinValue;
        private DateTime LastBearishAlertBarTime = DateTime.MinValue;
        private DateTime LastNeutralAlertBarTime = DateTime.MinValue;
        private bool AlertsInitialized = false;

        protected override void Initialize()
        {
            // MTF only when InputTimeFrame is strictly higher than the chart's; equal or lower falls back to chart TF.
            if (InputTimeFrame != null && InputTimeFrame > TimeFrame)
            {
                MtfBars = MarketData.GetBars(InputTimeFrame);
                IsMtf = true;
            }
            else
            {
                MtfBars = Bars;
                IsMtf = false;
            }

            emaHigh  = Indicators.MovingAverage(MtfBars.HighPrices,  EMA_Period, MA_Type);
            emaClose = Indicators.MovingAverage(MtfBars.ClosePrices, EMA_Period, MA_Type);
            emaLow   = Indicators.MovingAverage(MtfBars.LowPrices,   EMA_Period, MA_Type);

            MtfColor = CreateDataSeries();

            // Wipe bar colors left by a previous instance (parameter changes don't auto-reset them).
            Chart.ResetBarColors();
        }

        public override void Calculate(int index)
        {
            int colorIdx = ComputeColor(index, out double emaH, out double emaC, out double emaL);
            if (colorIdx < 0) return;

            ApplyBarState(index, colorIdx, emaH, emaC, emaL);

            if (!IsLastBar) return;

            // Live tick: in MTF the live HTF's EMA evolves each tick - re-stamp every LTF inside it.
            if (IsMtf)
            {
                int liveMtfIdx = GetMtfIndex(index);
                if (liveMtfIdx >= 0)
                {
                    int iFirst = index;
                    while (iFirst > 0 && GetMtfIndex(iFirst - 1) == liveMtfIdx) iFirst--;
                    for (int i = iFirst; i < index; i++)
                        ApplyBarState(i, colorIdx, emaH, emaC, emaL);
                }
            }

            CheckAlerts(index);
        }

        // Write LTF state: classification, EMA outputs, bar colors. Outline = trend color (this also colors the wick); fill = trend color for bullish bars, BearishBodyColor for bearish bars.
        private void ApplyBarState(int index, int colorIdx, double emaH, double emaC, double emaL)
        {
            MtfColor[index]        = colorIdx;
            EMA_HighOutput[index]  = emaH;
            EMA_CloseOutput[index] = emaC;
            EMA_LowOutput[index]   = emaL;

            if (!ShowGRaBCandles) return;

            Color trendColor = colorIdx == 0 ? GreenCandleColor : colorIdx == 1 ? RedCandleColor : BlueCandleColor;
            Color fillColor  = Bars.ClosePrices[index] >= Bars.OpenPrices[index] ? trendColor : BearishBodyColor;

            Chart.SetBarOutlineColor(index, trendColor);
            Chart.SetBarFillColor   (index, fillColor);
        }

        // Look up HTF (or chart-TF) EMAs for this LTF and classify against the wave channel (min/max of the 3 EMAs - robust during reversals when EMA(High)/EMA(Low) momentarily cross).
        private int ComputeColor(int index, out double emaH, out double emaC, out double emaL)
        {
            emaH = emaC = emaL = double.NaN;

            int mtfIdx = IsMtf ? GetMtfIndex(index) : index;
            if (mtfIdx < 0) return -1;

            emaH = emaHigh.Result[mtfIdx];
            emaC = emaClose.Result[mtfIdx];
            emaL = emaLow.Result[mtfIdx];
            if (double.IsNaN(emaH) || double.IsNaN(emaC) || double.IsNaN(emaL)) return -1;

            double waveTop = Math.Max(emaH, Math.Max(emaC, emaL));
            double waveBot = Math.Min(emaH, Math.Min(emaC, emaL));
            double cmpHigh = IsMtf ? MtfBars.HighPrices[mtfIdx] : Bars.HighPrices[index];
            double cmpLow  = IsMtf ? MtfBars.LowPrices [mtfIdx] : Bars.LowPrices [index];

            if      (cmpLow  > waveTop) return 0; // GREEN: bar fully above the Wave.
            else if (cmpHigh < waveBot) return 1; // RED:   bar fully below the Wave.
            else                        return 2; // BLUE:  bar overlaps the Wave.
        }

        // Map LTF index to its containing MTF bar via binary search on MtfBars.OpenTimes; -1 if the LTF predates MTF history.
        private int GetMtfIndex(int currentIndex)
        {
            DateTime currentTime = Bars.OpenTimes[currentIndex];

            int left = 0;
            int right = MtfBars.Count - 1;
            while (left <= right)
            {
                int mid = (left + right) / 2;
                DateTime mtfTime = MtfBars.OpenTimes[mid];

                if (currentTime >= mtfTime && (mid == MtfBars.Count - 1 || currentTime < MtfBars.OpenTimes[mid + 1]))
                    return mid;
                if (currentTime < mtfTime) right = mid - 1;
                else left = mid + 1;
            }
            return -1;
        }

        // Inverse of GetMtfIndex: first LTF index whose OpenTime >= the MTF bar's OpenTime. CheckAlerts uses it to pick a representative LTF per HTF.
        private int FindFirstLtfOfMtf(int mtfIdx)
        {
            if (mtfIdx < 0 || mtfIdx >= MtfBars.Count) return -1;
            DateTime mtfTime = MtfBars.OpenTimes[mtfIdx];

            int left = 0;
            int right = Bars.Count - 1;
            while (left <= right)
            {
                int mid = (left + right) / 2;
                if (Bars.OpenTimes[mid] >= mtfTime)
                {
                    if (mid == 0 || Bars.OpenTimes[mid - 1] < mtfTime) return mid;
                    right = mid - 1;
                }
                else left = mid + 1;
            }
            return -1;
        }

        // Fire alerts on color transitions. HTF pair in MTF (via FindFirstLtfOfMtf), LTF pair otherwise. Per-alert-type bar-time dedup + warmup gate.
        private void CheckAlerts(int index)
        {
            if (!BullishAlerts && !BearishAlerts && !NeutralAlerts) return;
            if (!EnableNativeAlerts && !EnableEmailAlerts && !EnableSoundAlerts) return;

            int minBars = (TriggerCandle == CandleToCheck.ClosedCandle) ? 3 : 2;

            int colorNew, colorOld;
            DateTime alertBarTime;

            if (IsMtf)
            {
                if (MtfBars.Count < minBars) return;
                int liveMtfIdx = MtfBars.Count - 1;
                // ClosedCandle: HTF[just-closed] vs HTF[two-back]. CurrentCandle: HTF[live] vs HTF[just-closed].
                int htfNew = (TriggerCandle == CandleToCheck.ClosedCandle) ? liveMtfIdx - 1 : liveMtfIdx;
                int htfOld = htfNew - 1;
                if (htfOld < 0) return;

                int iNew = FindFirstLtfOfMtf(htfNew);
                int iOld = FindFirstLtfOfMtf(htfOld);
                if (iNew < 0 || iOld < 0) return;

                double cNew = MtfColor[iNew], cOld = MtfColor[iOld];
                if (double.IsNaN(cNew) || double.IsNaN(cOld)) return;
                colorNew = (int)cNew; colorOld = (int)cOld;
                alertBarTime = MtfBars.OpenTimes[htfNew];
            }
            else
            {
                if (index + 1 < minBars) return;
                int idxNew = (TriggerCandle == CandleToCheck.ClosedCandle) ? index - 1 : index;
                int idxOld = idxNew - 1;
                if (idxOld < 0) return;

                double cNew = MtfColor[idxNew], cOld = MtfColor[idxOld];
                if (double.IsNaN(cNew) || double.IsNaN(cOld)) return;
                colorNew = (int)cNew; colorOld = (int)cOld;
                alertBarTime = Bars.OpenTimes[idxNew];
            }

            // Warmup: stamp guards on first run, don't fire.
            if (!AlertsInitialized)
            {
                LastBullishAlertBarTime = LastBearishAlertBarTime = LastNeutralAlertBarTime = alertBarTime;
                AlertsInitialized = true;
                return;
            }

            if (colorNew == colorOld) return;

            string tfStr = IsMtf ? InputTimeFrame.ToString() : Chart.TimeFrame.ToString();
            string mode  = (TriggerCandle == CandleToCheck.CurrentCandle) ? " [current bar]" : "";

            if (BullishAlerts && colorNew == 0 && LastBullishAlertBarTime != alertBarTime)
            {
                FireAlert("RagheeHorner Horner Bullish", $"{Symbol.Name} {tfStr}: New Bullish (Green) candle{mode}.", tfStr);
                LastBullishAlertBarTime = alertBarTime;
            }
            if (BearishAlerts && colorNew == 1 && LastBearishAlertBarTime != alertBarTime)
            {
                FireAlert("RagheeHorner Horner Bearish", $"{Symbol.Name} {tfStr}: New Bearish (Red) candle{mode}.", tfStr);
                LastBearishAlertBarTime = alertBarTime;
            }
            if (NeutralAlerts && colorNew == 2 && LastNeutralAlertBarTime != alertBarTime)
            {
                FireAlert("RagheeHorner Horner Neutral", $"{Symbol.Name} {tfStr}: New Neutral (Blue) candle{mode}.", tfStr);
                LastNeutralAlertBarTime = alertBarTime;
            }
        }

        // Dispatch alert through every enabled channel. Popup gets bare message (cTrader adds context columns); email gets broker/account header.
        private void FireAlert(string title, string message, string tfStr)
        {
            if (EnableNativeAlerts)
            {
                Notifications.ShowPopup(title, message, PopupNotificationState.Information);
                Print(message);
            }
            if (EnableEmailAlerts && !string.IsNullOrEmpty(EmailAddress))
            {
                string subject = $"RagheeHorner Horner {Symbol.Name} {title} ({tfStr})";
                string body    = $"{Account.BrokerName} - {Account.Number}\n{message}\nTime: {Server.Time}";
                Notifications.SendEmail(EmailAddress, EmailAddress, subject, body);
            }
            if (EnableSoundAlerts) Notifications.PlaySound(SoundType);
        }
    }
}