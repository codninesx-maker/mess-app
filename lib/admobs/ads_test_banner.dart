import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_helper.dart';

class MessTestBanner extends StatefulWidget {
  final AdSize adSize;
  const MessTestBanner({super.key, this.adSize = AdSize.banner});

  @override
  State<MessTestBanner> createState() => _MessTestBannerState();
}

class _MessTestBannerState extends State<MessTestBanner> with AutomaticKeepAliveClientMixin {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAd();
    });
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadAd() {
    if (!mounted) return;

    // Clean up any stale references
    _bannerAd?.dispose();
    _bannerAd = null;
    if (_isLoaded) {
      setState(() => _isLoaded = false);
    }

    debugPrint("Mess_UI_ADS: Requesting banner...");

    _bannerAd = BannerAd(
      adUnitId: AdHelper.bannerAdUnitId,
      size: widget.adSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint("Mess_UI_ADS: Error: ${error.message}");
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _isLoaded = false;
          });
        },
      ),
    );

    // Asynchronous load with hot-restart collision auto-recovery
    _bannerAd!.load().catchError((error) {
      debugPrint("Ad load platform exception (Hot Restart collision detected): $error");

      // Clear out the failed instance
      _bannerAd = null;
      if (mounted) {
        setState(() => _isLoaded = false);
      }

      // Automatically retry loading a fresh ad instance after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _loadAd();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}