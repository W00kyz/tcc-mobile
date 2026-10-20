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

  // --- route screen ---
  static const String routeAppBarTitle = 'Rota de hoje';
  static const String routeLoadError = 'Não foi possível carregar sua rota.';
  static const String routeEmpty = 'Nenhuma rota atribuída para hoje.';
  static const String routeViewMapButton = 'Ver no mapa';
  static const String routeStartButton = 'Iniciar rota';
  static const String routeCheckInButton = 'Fazer check-in';
  static const String routeStartedHeader = 'Rota iniciada';
  static const String routeNotStartedHeader = 'Rota não iniciada';
  static const String routeOccasionalChip = 'EVENTUAL';
  static const String routeStopReassignedChip = 'Reatribuído';
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

  /// The arrival-window subtitle, e.g. `Janela: 08:00–08:30`.
  static String routeWindow(String window) => 'Janela: $window';

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
  static const String blockedSyncKindStartRoute = 'Início de rota';
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
}
