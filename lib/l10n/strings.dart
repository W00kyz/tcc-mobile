/// Every user-facing pt-BR string in the app, in one place (RNF02).
///
/// Widgets never hold literal copy — they reference `AppStrings.*`. This is a
/// plain constant table, not a full i18n framework: the app ships pt-BR only
/// (Android, PU/UFCG field workers), so a `Locale`-aware `.arb` toolchain would
/// be machinery with no second locale to justify it. Interpolation and
/// pluralization are `static String name(...)` helpers.
///
/// Example:
/// ```dart
/// AppBar(title: const Text(AppStrings.routeAppBarTitle));
/// Text(AppStrings.routePendingSync(count));
/// ```
abstract final class AppStrings {
  // --- common (shared across screens) ---
  static const String commonCancel = 'Cancelar';
  static const String commonConfirm = 'Confirmar';
  static const String commonSave = 'Salvar';
  static const String commonBack = 'Voltar';

  /// A distance rendered as `<n> m` (candidate tiles, route legs).
  static String meters(int m) => '$m m';

  // --- login ---
  static const String loginBrand = 'PU · UFCG';
  static const String loginTitle = 'Monitoramento de Rotas';
  static const String loginEmailLabel = 'E-mail';
  static const String loginPasswordLabel = 'Senha';
  static const String loginSubmitButton = 'Entrar';
  static const String loginSubmitting = 'Entrando…';
  static const String loginInvalidCredentials = 'E-mail ou senha incorretos.';
  static const String loginNetworkError =
      'Sem conexão com o servidor. Tente novamente quando houver sinal.';
  static const String loginForgotPassword = 'Esqueci minha senha';
  static const String forgotPasswordTitle = 'Recuperar senha';
  static const String forgotPasswordIntro =
      'Informe seu e-mail cadastrado. Enviaremos um link para definir uma '
      'nova senha.';
  static const String forgotPasswordSend = 'Enviar link';
  static const String forgotPasswordCancel = 'Cancelar';
  static const String forgotPasswordSent =
      'Se o e-mail estiver cadastrado, você receberá um link em instantes.';
  static const String forgotPasswordError =
      'Não foi possível enviar o link. Verifique a conexão e tente novamente.';
  static const String loginCreateAccount = 'Criar conta';

  // --- self-registration (alocação automática §9) ---
  static const String registrationTitle = 'Criar conta';
  static const String registrationNameLabel = 'Nome';
  static const String registrationEmailLabel = 'E-mail';
  static const String registrationPasswordLabel = 'Senha';
  static const String registrationCompanyLabel = 'Empresa';
  static const String registrationNameRequired = 'Informe seu nome.';
  static const String registrationEmailInvalid = 'Informe um e-mail válido.';
  static const String registrationPasswordTooShort =
      'A senha precisa ter pelo menos 8 caracteres.';
  static const String registrationPasswordTooLong =
      'A senha pode ter no máximo 128 caracteres.';
  static const String registrationCompanyRequired = 'Escolha sua empresa.';
  static const String registrationAcceptNotice = 'Li e aceito';
  static const String registrationSubmit = 'Enviar cadastro';
  static const String registrationSubmitting = 'Enviando…';
  static const String registrationSent =
      'Cadastro enviado. Aguarde a aprovação do gestor.';
  static const String registrationEmailTaken =
      'Este e-mail já está cadastrado.';
  static const String registrationNoticeOutdated =
      'O aviso de privacidade foi atualizado. Leia e aceite a nova versão.';
  static const String registrationError =
      'Não foi possível enviar o cadastro. Verifique a conexão e tente '
      'novamente.';
  static const String registrationInvalidData =
      'Verifique os dados informados.';
  static const String registrationCompanyGone =
      'A empresa escolhida não está mais disponível. Escolha novamente.';
  static const String registrationServerError =
      'O servidor não conseguiu registrar o cadastro. Tente novamente mais '
      'tarde.';
  static const String registrationLoadError =
      'Não foi possível carregar as empresas e o aviso de privacidade.';
  static const String registrationRetry = 'Tentar novamente';

  /// The `Versão <n>` label under the privacy notice title.
  static String registrationNoticeVersion(int version) => 'Versão $version';

  // --- approval gate (alocação automática §9) ---
  static const String approvalPendingMessage =
      'Seu cadastro está aguardando aprovação do gestor.';
  static const String approvalRejectedMessage =
      'Seu cadastro não foi aprovado.';
  static const String approvalDeactivatedMessage =
      'Seu cadastro foi desativado pelo gestor.';
  static const String approvalRefreshButton = 'Atualizar';
  static const String approvalExitButton = 'Sair';
  static const String approvalStillPending =
      'Seu cadastro ainda aguarda aprovação.';
  static const String approvalNetworkError =
      'Sem conexão com o servidor. Tente novamente quando houver sinal.';

  /// The manager's reason under a rejection.
  static String approvalRejectionReason(String reason) => 'Motivo: $reason';

  // --- route screen ---
  static const String routeAppBarTitle = 'Rota de hoje';
  static const String routeLoadError = 'Não foi possível carregar sua rota.';
  static const String routeViewMapButton = 'Ver no mapa';
  static const String routeStartButton = 'Iniciar rota';
  static const String routeCheckInButton = 'Fazer check-in';
  static const String formMediaTakePhoto = 'Tirar foto';
  static const String formMediaRemove = 'Remover foto';
  static const String formMediaLimit = 'Limite de 10 fotos por pergunta.';
  static const String routeConcludeButton = 'Concluir';
  static const String routeFillFormButton = 'Preencher formulário';
  static const String routeFormIncompleteHint =
      'Preencha o formulário para concluir.';
  static const String routeSignalImpossibilityButton =
      'Sinalizar impossibilidade';
  static const String routeNotificationsTooltip = 'Notificações';
  static const String routeCheckInDone = 'Check-in registrado.';
  static const String routeCheckOutDone = 'Check-out registrado.';
  static const String routeImpedimentReported = 'Impossibilidade sinalizada.';
  static const String routeLocationUnavailable =
      'Não foi possível obter sua localização.';
  static const String routeLocationUnavailableCheckIn =
      'Não foi possível obter sua localização; check-in seguirá sem GPS.';

  // --- route screen · batches (spec 2026-10-20-alocacao-automatica §6.4) ---
  static const String routeNotServiceDay = 'Hoje não é dia de serviço.';
  static const String routeStartOffline =
      'Conecte-se à internet para iniciar a rota.';
  static const String routeOutsideCampus =
      'Você precisa estar no campus para iniciar.';
  static const String routeWorkdayOver = 'O expediente de hoje já terminou.';
  static const String routeNoMorePoints = 'Não há mais pontos hoje.';
  static const String routeStartFailed =
      'Não foi possível iniciar a rota. Tente novamente.';
  static const String routePausedTitle = 'Seus pontos foram liberados';
  static const String routeNextBatchOffline =
      'Conecte-se para receber mais pontos';

  /// `Lote <n> · <x> ponto(s) feito(s) hoje`.
  static String routeBatchHeader(int batch, int doneToday) =>
      'Lote $batch · $doneToday '
      '${doneToday == 1 ? 'ponto feito' : 'pontos feitos'} hoje';

  /// Why a paused route's points went back to the pool.
  static String routePausedReason(String reason) => 'Motivo: $reason';

  /// A stop's `release_reason` code in words (same labels as the dashboard).
  static String releaseReasonLabel(String code) => switch (code) {
    'IMPEDIMENT' => 'Impedimento',
    'ROUTE_REMAINDER' => 'Resto da rota impedido',
    'LEFT_CAMPUS' => 'Saiu do campus',
    'LOCATION_SILENCE' => 'Sem localização',
    'END_OF_DAY' => 'Fim do expediente',
    _ => code,
  };

  // --- route screen · sync banner ---
  static const String routeSyncBlockedBanner =
      'Sincronização bloqueada — toque para ver';
  static const String routeSyncNowButton = 'Sincronizar agora';
  static const String routeAllSynced = 'Tudo sincronizado';
  static const String routeChipPending = 'Pendente';
  static const String routeChipBlocked = 'Bloqueado';

  /// `<n> ação(ões) aguardando sincronização`.
  static String routePendingSync(int n) =>
      '$n ${n == 1 ? 'ação' : 'ações'} aguardando sincronização';

  /// The travel-from-previous leg line, e.g. `a 120 m · 2 min`.
  static String routeLeg(String leg) => 'a $leg';

  // --- route screen · evidence ---
  static const String routeAddPhotoButton = 'Adicionar foto';
  static const String routeAddNoteButton = 'Adicionar observação';
  static const String routeNoteHint = 'Descreva a observação';
  static const String routeEvidencePhotoLabel = 'Foto';
  static const String routeEvidenceLoadError =
      'Não foi possível carregar as evidências.';
  static const String routePhotoAdded = 'Foto adicionada.';
  static const String routePhotoAddError = 'Não foi possível adicionar a foto.';
  static const String routeNoteAdded = 'Observação adicionada.';
  static const String routeNoteAddError =
      'Não foi possível adicionar a observação.';

  // --- map screen ---
  static const String mapAppBarTitle = 'Trajeto da rota';
  static const String mapApproximateLegLabel = 'trajeto aproximado';

  // --- scan screen ---
  static const String scanAppBarTitle = 'Ler QR Code';
  static const String scanInvalidQr = 'QR Code inválido ou adulterado.';

  // --- blocked sync screen ---
  static const String blockedSyncAppBarTitle = 'Sincronização bloqueada';
  static const String blockedSyncLoadError =
      'Não foi possível carregar as operações bloqueadas.';
  static const String blockedSyncEmpty = 'Nenhuma operação bloqueada.';
  static const String blockedSyncRetryButton = 'Tentar de novo';
  static const String blockedSyncUnknownError = 'Erro desconhecido';
  static const String blockedSyncKindCheckIn = 'Check-in';
  static const String blockedSyncKindCheckOut = 'Check-out';
  static const String blockedSyncKindPhoto = 'Foto';
  static const String blockedSyncKindNote = 'Observação';
  static const String blockedSyncKindImpediment = 'Impedimento';

  /// A `<kind> — <reference>` outbox-row label.
  static String blockedSyncRowLabel(String kind, String reference) =>
      '$kind — $reference';

  // --- room picker ---
  static const String roomPickerPrompt =
      'Vários pontos correspondem — escolha o certo:';

  // --- impediment dialog ---
  static const String impedimentDialogTitle = 'Sinalizar impossibilidade';
  static const String impedimentNoteHint = 'Observação (opcional)';
  static const String impedimentRemainderSwitch =
      'Sinalizar para o resto da rota também';
  static const String impedimentReasonAccessBlocked = 'Acesso bloqueado';
  static const String impedimentReasonSiteRefusal = 'Recusa do local';
  static const String impedimentReasonHealthIssue = 'Problema de saúde';
  static const String impedimentReasonOther = 'Outro';

  // --- form screen ---
  static const String formAppBarTitle = 'Formulário';
  static const String formLoadError = 'Não foi possível carregar o formulário.';
  static const String formQuestionChanged =
      'Esta pergunta mudou — responda de novo.';
  static const String formComplete = 'Formulário completo';
  static const String formAddNoteDialogTitle = 'Adicionar observação';

  /// A required question's prompt, suffixed `(obrigatória)`.
  static String formRequiredPrompt(String prompt) => '$prompt (obrigatória)';

  /// `<n> pendências` remaining in the draft footer.
  static String formPending(int n) => '$n pendências';

  // --- notifications screen ---
  static const String notificationsAppBarTitle = 'Notificações';
  static const String notificationsLoadError =
      'Não foi possível carregar as notificações.';
  static const String notificationsEmpty = 'Nenhuma notificação.';
  static const String notificationKindAlert = 'Alerta';
  static const String notificationKindRouteAssigned = 'Nova rota';
  static const String notificationKindRouteModified = 'Rota alterada';
  static const String notificationKindStopReassigned = 'Ponto reatribuído';

  /// `<kind> · <timestamp>` metadata line under a notification.
  static String notificationMeta(String kind, String timestamp) =>
      '$kind · $timestamp';

  // --- consent gate (Etapa 11 Task 10) ---
  static const String consentTitle = 'Antes de continuar';
  static const String consentBody =
      '[Texto de consentimento — placeholder. A Prefeitura Universitária da '
      'UFCG coleta seus dados de identificação, localização durante a jornada '
      'de trabalho e registros de execução de rota para fins de fiscalização '
      'da prestação de serviços (LGPD, art. 7º). O tratamento segue a '
      'finalidade descrita e os dados são retidos pelo prazo definido na '
      'política interna. Substituir por texto revisado pelo DPO antes do '
      'piloto.]';
  static const String consentAcceptButton = 'Li e concordo';
  static const String consentLoadError =
      'Não foi possível carregar o termo de consentimento.';
  static const String consentExitButton = 'Sair';

  // --- "meus dados" screen (Etapa 11 Task 11) ---
  static const String myDataTitle = 'Meus dados';
  static const String myDataLoading = 'Carregando seus dados…';
  static const String myDataError = 'Não foi possível carregar seus dados.';
  static const String myDataEmpty = 'Nenhum dado registrado.';
  static const String myDataSectionProfile = 'Perfil';
  static const String myDataSectionConsent = 'Consentimento';
  static const String myDataSectionActivity = 'Atividade';
  static const String myDataSectionFieldWorker = 'Cadastro de campo';
  static const String myDataSectionAuthEvents = 'Acessos à conta';
  static const String myDataSectionExecutions = 'Execuções de rota';
  static const String myDataSectionEvidence = 'Evidências';
  static const String myDataSectionPositions = 'Registros de localização';
  static const String myDataSectionNotifications = 'Notificações';
  static const String myDataFieldEmail = 'E-mail';
  static const String myDataFieldName = 'Nome';
  static const String myDataFieldRole = 'Perfil de acesso';
  static const String myDataFieldActive = 'Conta ativa';
  static const String myDataFieldInactive = 'Conta inativa';
  static const String myDataFieldCreatedAt = 'Criada em';
  static const String myDataFieldFullName = 'Nome completo';
  static const String myDataFieldCompany = 'Empresa contratada';
  static const String myDataFieldServiceTypes = 'Tipos de serviço';
  static const String myDataFieldTotal = 'Total';
  static const String myDataFieldFirstAt = 'Primeiro registro';
  static const String myDataFieldLastAt = 'Último registro';
  static const String myDataFieldEvidenceItems = 'Itens';
  static const String myDataFieldEvidenceBytes = 'Tamanho aproximado';
  static const String myDataFieldNotificationsUnread = 'Não lidas';

  /// A `versão <n>` label for a consent-history entry.
  static String myDataConsentVersion(int version) => 'versão $version';

  /// An approximate size rendered in kilobytes, e.g. `~ 1234 KB`.
  static String myDataKilobytes(int bytes) => '~ ${(bytes / 1024).round()} KB';

  // --- data-collection notice (Etapa 11 Task 12) ---
  static const String collectionNotificationTitle =
      'Coleta de localização ativa';
  static const String collectionNotificationBody =
      'Sua localização está sendo registrada durante a rota para fins de '
      'fiscalização.';
  static const String collectionBannerText =
      'Coleta de localização ativa durante a rota.';
  static const String collectionNotificationChannelName =
      'Coleta de localização';
  static const String collectionNotificationChannelDescription =
      'Aviso persistente enquanto a localização é registrada durante a rota.';
  static const String locationPurposeRationale =
      'A localização é usada apenas para confirmar a presença nos pontos da '
      'rota e não é compartilhada fora da Prefeitura Universitária.';

  // --- location in two modes and the silence warning (alocação §7.3) ---
  /// The fixed notification of the background-location foreground service.
  static const String routeInProgressTitle = 'Rota em andamento';
  static const String routeInProgressText = collectionNotificationBody;
  static const String locationAlwaysRationale =
      'Para não perder seus pontos com a tela bloqueada, permita a '
      'localização o tempo todo durante a rota.';
  static const String locationForegroundOnlyNote =
      'Sem essa permissão, abra o app de tempos em tempos durante a rota.';
  static const String locationPromptContinue = 'Continuar';
  static const String locationPromptUnderstood = 'Entendi';
  static const String silenceNotificationTitle = 'Localização não enviada';
  static const String silenceNotificationChannelName = 'Aviso de localização';
  static const String silenceNotificationChannelDescription =
      'Avisa quando a localização não é enviada há algum tempo durante a '
      'rota.';

  /// The silence warning: [silent] minutes without a sent position, the
  /// points released in [untilRelease] minutes — or, with none left, the
  /// [silenceWarningPastRelease] copy.
  static String silenceWarning(int silent, int untilRelease) =>
      untilRelease <= 0
      ? silenceWarningPastRelease(silent)
      : 'Sem enviar sua localização há $silent min. Seus pontos serão '
            'liberados em $untilRelease min. Abra o app ou procure sinal.';

  /// The warning once the release window has run out.
  static String silenceWarningPastRelease(int silent) =>
      'Sem enviar sua localização há $silent min. Seus pontos podem ter '
      'sido liberados. Abra o app ou procure sinal.';
}
