object FrmConfigSincroniaAutomatica: TFrmConfigSincroniaAutomatica
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Sincronia Automática'
  ClientHeight = 220
  ClientWidth = 400
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  TextHeight = 15
  object pnlTopo: TPanel
    Left = 0
    Top = 0
    Width = 400
    Height = 50
    Align = alTop
    Color = clWhite
    ParentBackground = False
    TabOrder = 0
    object lblTitulo: TLabel
      Left = 16
      Top = 12
      Width = 220
      Height = 21
      Caption = 'Sincronia Automática (F2)'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
  end
  object chkAtivo: TCheckBox
    Left = 24
    Top = 68
    Width = 320
    Height = 21
    Caption = 'Ativar envio automático de estoque (F2 - Enviar Dados)'
    TabOrder = 0
  end
  object lblIntervalo: TLabel
    Left = 24
    Top = 104
    Width = 120
    Height = 15
    Caption = 'Intervalo de execução'
  end
  object edtIntervalo: TEdit
    Left = 24
    Top = 122
    Width = 100
    Height = 23
    TabOrder = 1
  end
  object lblSegundos: TLabel
    Left = 130
    Top = 125
    Width = 100
    Height = 15
    Caption = 'segundos (mínimo 10)'
  end
  object pnlRodape: TPanel
    Left = 0
    Top = 164
    Width = 400
    Height = 56
    Align = alBottom
    TabOrder = 2
    object CmdSalvar: TBitBtn
      Left = 174
      Top = 12
      Width = 100
      Height = 32
      Caption = 'Salvar'
      TabOrder = 0
      OnClick = CmdSalvarClick
    end
    object CmdCancelar: TBitBtn
      Left = 280
      Top = 12
      Width = 100
      Height = 32
      Caption = 'Cancelar'
      TabOrder = 1
      OnClick = CmdCancelarClick
    end
  end
end
