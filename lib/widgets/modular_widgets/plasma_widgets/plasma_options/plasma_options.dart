import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vector_icons/flutter_vector_icons.dart';
import 'package:provider/provider.dart';
import 'package:stacked/stacked.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/dashboard/balance_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/plasma/plasma_list_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/plasma/plasma_options_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/plasma/plasma_stats_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/model/plasma_info_wrapper.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';
import 'package:zenon_syrius_wallet_flutter/utils/extensions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/input_validators.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notification_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/default_address_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/plasma_beneficiary_address_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/loading_button.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/error_widget.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/input_field/amount_suffix_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/input_field/disabled_address_field.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/input_field/input_field.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/layout_scaffold/card_scaffold.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/loading_widget.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/plasma_icon.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/stepper_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class PlasmaOptions extends StatefulWidget {
  final List<PlasmaInfoWrapper> plasmaStatsResults;
  final String? errorText;
  final PlasmaListBloc plasmaListBloc;

  const PlasmaOptions({
    required this.plasmaListBloc,
    this.errorText,
    required this.plasmaStatsResults,
    Key? key,
  }) : super(key: key);

  @override
  State createState() {
    return _PlasmaOptionsState();
  }
}

class _PlasmaOptionsState extends State<PlasmaOptions> {
  final TextEditingController _qsrAmountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _beneficiaryAddressController =
      TextEditingController();
  final GlobalKey<FormState> _qsrAmountKey = GlobalKey();
  final GlobalKey<FormState> _beneficiaryAddressKey = GlobalKey();
  final GlobalKey<LoadingButtonState> _fuseButtonKey = GlobalKey();

  int? _maxQsrAmount;
  double? _maxWidth;

  final double _marginWidth = 20.0;
  final double _spaceBetweenExpandedWidgets = 10.0;
  final int _beneficiaryAddressExpandedFlex = 8;
  final int _fuseButtonExpandedFlex = 6;

  final ValueNotifier<String> _beneficiaryAddressString = ValueNotifier('');

  @override
  void initState() {
    super.initState();
    sl.get<BalanceBloc>().getBalanceForAllAddresses();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SelectedAddressNotifier>(
      builder: (_, __, child) {
        _addressController.text = kSelectedAddress!;
        return child!;
      },
      child: LayoutBuilder(
        builder: (_, constraints) {
          _maxWidth = constraints.maxWidth;
          return CardScaffold(
            title: 'Plasma Options',
            description:
                'This card displays information about Plasma available '
                'per wallet address. A minimum of 10 ${kQsrCoin.symbol} are needed to '
                'be fused in order to generate Plasma. The more ${kQsrCoin.symbol} '
                'fused, the more Plasma is produced for the beneficiary address\n\n'
                'Insufficient Plasma: Proof-of-work for Plasma generation; limited '
                'to 1 transaction per momentum\nLow Plasma: between 10 and 89 '
                '${kQsrCoin.symbol}\nAverage Plasma: between 90 and 119 '
                '${kQsrCoin.symbol}\nHigh Plasma: over 120 ${kQsrCoin.symbol}; '
                'recommended for complex transactions (register Pillars, '
                'Sentinels, staking and issuing ZTS tokens)',
            childBuilder: () => widget.errorText != null
                ? SyriusErrorWidget(widget.errorText!)
                : StreamBuilder<Map<String, AccountInfo>?>(
                    stream: sl.get<BalanceBloc>().stream,
                    builder: (_, snapshot) {
                      if (snapshot.hasError) {
                        return SyriusErrorWidget(snapshot.error!);
                      }
                      if (snapshot.connectionState == ConnectionState.active) {
                        if (snapshot.hasData) {
                          _maxQsrAmount =
                              snapshot.data![_addressController.text]!
                                  .getBalanceWithDecimals(
                                    kQsrCoin.tokenStandard,
                                  )
                                  .toInt();
                          return _getWidgetBody(
                            snapshot.data![_addressController.text],
                          );
                        }
                        return const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: SyriusLoadingWidget(),
                        );
                      }
                      return const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: SyriusLoadingWidget(),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }

  Widget _getWidgetBody(AccountInfo? accountInfo) {
    return Consumer<PlasmaBeneficiaryAddressNotifier>(
      builder: (_, notifier, child) {
        _beneficiaryAddressController.text = notifier.getBeneficiaryAddress()!;
        return Container(
          margin: EdgeInsets.all(_marginWidth),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: _beneficiaryAddressExpandedFlex,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    DisabledAddressField(
                      _addressController,
                      contentLeftPadding: 20.0,
                    ),
                    StepperUtils.getBalanceWidget(kQsrCoin, accountInfo!),
                    Form(
                      key: _beneficiaryAddressKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: InputField(
                        onChanged: (String value) {
                          _beneficiaryAddressString.value = value;
                        },
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9a-z]')),
                        ],
                        controller: _beneficiaryAddressController,
                        hintText: 'Beneficiary address',
                        contentLeftPadding: 20.0,
                        validator: (value) =>
                            InputValidators.checkAddress(value),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: _spaceBetweenExpandedWidgets,
              ),
              Expanded(
                flex: _fuseButtonExpandedFlex,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 87.0,
                      child: Form(
                        key: _qsrAmountKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: InputField(
                          enabled: _maxQsrAmount! > 0,
                          onChanged: (String value) {
                            // The setState() causes a redraw which resets the beneficiaryAddress.
                            // setState(() {});
                          },
                          inputFormatters:
                              FormatUtils.getPlasmaAmountTextInputFormatters(
                            _qsrAmountController.text,
                          ),
                          controller: _qsrAmountController,
                          validator: (value) => InputValidators.correctValue(
                            value,
                            _maxQsrAmount,
                            kQsrCoin.decimals,
                            min: fuseMinQsrAmount.addDecimals(
                              qsrDecimals,
                            ),
                            canBeEqualToMin: true,
                          ),
                          suffixIcon: _getAmountSuffix(),
                          hintText: 'Amount',
                          contentLeftPadding: 20.0,
                        ),
                      ),
                    ),
                    ValueListenableBuilder<String>(
                      valueListenable: _beneficiaryAddressString,
                      builder: (_, __, ___) {
                        return Row(
                          children: [
                            _getGeneratePlasmaButtonStreamBuilder(),
                            Visibility(
                              visible: _isInputValid(),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 10.0,
                                  ),
                                  _getPlasmaIcon(),
                                ],
                              ),
                            )
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PlasmaIcon _getPlasmaIcon() {
    return PlasmaIcon(
      PlasmaInfo.fromJson(
        {
          'currentPlasma': (_qsrAmountController.text.isNotEmpty
                  ? zenon!.embedded.plasma.getPlasmaByQsr(
                      double.parse(_qsrAmountController.text),
                    )
                  : 0) +
              _getPlasmaForCurrentBeneficiary(),
          'maxPlasma': 0,
          'qsrAmount': 0,
        },
      ),
    );
  }

  int _getPlasmaForCurrentBeneficiary() {
    try {
      return widget.plasmaStatsResults
          .firstWhere(
            (plasmaInfo) =>
                plasmaInfo.address == _beneficiaryAddressController.text,
          )
          .plasmaInfo
          .currentPlasma;
    } catch (e) {
      return 0;
    }
  }

  Widget _getGeneratePlasmaButton(PlasmaOptionsBloc model) {
    Widget icon = Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.qsrColor,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 15.0),
      child: const Icon(
        MaterialCommunityIcons.lightning_bolt,
        size: 15.0,
        color: Colors.white,
      ),
    );

    double widthOfPlasmaIcon = _isInputValid() ? 20.0 : 0.0;
    double plasmaIconMargin = _isInputValid() ? 10.0 : 0.0;

    return LoadingButton.icon(
      onPressed: _isInputValid() ? () => _onGeneratePlasmaPressed(model) : null,
      label: 'Fuse',
      outlineColor: AppColors.qsrColor,
      icon: icon,
      minimumSize: Size(
          ((_maxWidth! - _marginWidth * 2 - _spaceBetweenExpandedWidgets) /
                  (_beneficiaryAddressExpandedFlex + _fuseButtonExpandedFlex) *
                  _fuseButtonExpandedFlex -
              widthOfPlasmaIcon -
              plasmaIconMargin),
          40.0),
      key: _fuseButtonKey,
    );
  }

  void _onGeneratePlasmaPressed(PlasmaOptionsBloc? model) {
    if (_isInputValid()) {
      _fuseButtonKey.currentState?.animateForward();
      model!.generatePlasma(
        _beneficiaryAddressController.text,
        _qsrAmountController.text,
      );
    }
  }

  Widget _getAmountSuffix() {
    return AmountSuffixWidgets(
      kQsrCoin,
      onMaxPressed: _onMaxPressed,
    );
  }

  void _onMaxPressed() {
    if (_qsrAmountController.text.isEmpty ||
        _qsrAmountController.text.toNum() != _maxQsrAmount) {
      setState(() {
        _qsrAmountController.text = _maxQsrAmount!.toString();
      });
    }
  }

  Widget _getGeneratePlasmaButtonStreamBuilder() {
    return ViewModelBuilder<PlasmaOptionsBloc>.reactive(
      onModelReady: (model) {
        model.stream.listen(
          (event) {
            if (event != null) {
              _fuseButtonKey.currentState?.animateReverse();
              _qsrAmountKey.currentState?.reset();
              _qsrAmountController.clear();
              sl.get<PlasmaStatsBloc>().getPlasmas();
              widget.plasmaListBloc.refreshResults();
            }
          },
          onError: (error) {
            _fuseButtonKey.currentState?.animateReverse();
            NotificationUtils.sendNotificationError(
              error,
              'Error while generating Plasma',
            );
          },
        );
      },
      builder: (_, model, __) => _getGeneratePlasmaButton(model),
      viewModelBuilder: () => PlasmaOptionsBloc(),
    );
  }

  bool _isInputValid() =>
      _qsrAmountController.text.isNotEmpty &&
      _beneficiaryAddressController.text.isNotEmpty &&
      InputValidators.checkAddress(
            _beneficiaryAddressController.text,
          ) ==
          null &&
      InputValidators.correctValue(
            _qsrAmountController.text,
            _maxQsrAmount,
            kQsrCoin.decimals,
            min: fuseMinQsrAmount.addDecimals(
              qsrDecimals,
            ),
            canBeEqualToMin: true,
          ) ==
          null;

  @override
  void dispose() {
    _qsrAmountController.dispose();
    _addressController.dispose();
    _beneficiaryAddressController.dispose();
    super.dispose();
  }
}
