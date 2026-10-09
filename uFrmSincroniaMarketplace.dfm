object FrmSincroniaMarketplace: TFrmSincroniaMarketplace
  Left = 0
  Top = 0
  Caption = 'SAT - Sincronia Marketplace'
  ClientHeight = 460
  ClientWidth = 700
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Menu = MainMenu1
  Position = poScreenCenter
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  TextHeight = 15
  object pnlTopo: TPanel
    Left = 0
    Top = 0
    Width = 700
    Height = 100
    Align = alTop
    Color = clWhite
    ParentBackground = False
    TabOrder = 0
    ExplicitWidth = 698
    object lblTitulo: TLabel
      Left = 16
      Top = 12
      Width = 171
      Height = 21
      Caption = 'Sincronia Marketplace'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object lblLojaConectada: TLabel
      Left = 16
      Top = 70
      Width = 203
      Height = 15
      Caption = 'Carregando informa'#231#245'es da conex'#227'o...'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGrayText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object lblSelecioneLoja: TLabel
      Left = 260
      Top = 15
      Width = 25
      Height = 15
      Caption = 'Loja:'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object cbxLoja: TComboBox
      Left = 300
      Top = 12
      Width = 384
      Height = 23
      Style = csDropDownList
      TabOrder = 0
      OnChange = cbxLojaChange
    end
  end
  object pnlLeft: TPanel
    Left = 0
    Top = 100
    Width = 89
    Height = 360
    Align = alLeft
    TabOrder = 1
    ExplicitHeight = 352
    object CmdEnviarDados: TBitBtn
      Left = 4
      Top = 8
      Width = 80
      Height = 70
      Caption = 'F2 - Envia Dados'
      Layout = blGlyphTop
      Margin = 5
      Spacing = 5
      TabOrder = 0
      WordWrap = True
      OnClick = CmdEnviarDadosClick
    end
    object CmdReceberDados: TBitBtn
      Left = 4
      Top = 84
      Width = 80
      Height = 70
      Caption = 'F3 - Receber Ofertas'
      Layout = blGlyphTop
      Margin = 5
      Spacing = 5
      TabOrder = 1
      WordWrap = True
      OnClick = CmdReceberDadosClick
    end
    object CmdPedidos: TBitBtn
      Left = 4
      Top = 160
      Width = 80
      Height = 70
      Caption = 'F4 - Pedidos'
      Layout = blGlyphTop
      Margin = 5
      Spacing = 5
      TabOrder = 2
      WordWrap = True
      OnClick = CmdPedidosClick
    end
    object CmdConfigSincroniaAutomatica: TBitBtn
      Left = 4
      Top = 236
      Width = 80
      Height = 70
      Caption = 'Auto: OFF'
      Layout = blGlyphTop
      Margin = 5
      Spacing = 5
      TabOrder = 3
      WordWrap = True
      OnClick = CmdConfigSincroniaAutomaticaClick
    end
  end
  object pnlPrincipal: TPanel
    Left = 89
    Top = 100
    Width = 611
    Height = 360
    Align = alClient
    TabOrder = 2
    ExplicitWidth = 609
    ExplicitHeight = 352
    object lblCompilacao: TLabel
      Left = 16
      Top = 366
      Width = 3
      Height = 15
    end
    object MemoLog: TMemo
      Left = 16
      Top = 16
      Width = 579
      Height = 340
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Consolas'
      Font.Style = []
      ParentFont = False
      ReadOnly = True
      ScrollBars = ssVertical
      TabOrder = 0
    end
  end
  object TrayIcon: TTrayIcon
    PopupMenu = TrayPopup
    OnDblClick = TrayIconDblClick
    Left = 620
    Top = 16
  end
  object TrayPopup: TPopupMenu
    Left = 620
    Top = 56
    object miExibir: TMenuItem
      Caption = 'Exibir'
      OnClick = miExibirClick
    end
    object N1: TMenuItem
      Caption = '-'
    end
    object miSair: TMenuItem
      Caption = 'Sair'
      OnClick = miSairClick
    end
  end
  object MainMenu1: TMainMenu
    Left = 620
    Top = 96
    object mnuOpcoes: TMenuItem
      Caption = 'Op'#231#245'es'
      object mnuMinimizar: TMenuItem
        Caption = 'Minimizar'
        OnClick = mnuMinimizarClick
      end
      object mnuSair: TMenuItem
        Caption = 'Sair'
        OnClick = mnuSairClick
      end
    end
    object mnuSincronizar: TMenuItem
      Caption = 'Sincronizar'
      object mnuReceberOfertas: TMenuItem
        Caption = 'Receber Ofertas do Marketplace'
        OnClick = mnuReceberOfertasClick
      end
    end
  end
  object TmrSincroniaAutomatica: TTimer
    Enabled = False
    Interval = 120000
    OnTimer = TmrSincroniaAutomaticaTimer
    Left = 600
    Top = 16
  end
end
